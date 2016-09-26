#!/bin/bash
# Shell script to create a backend Web server using docker containers
# Created by Tamas Meszaros <mt+git@webit.hu>

function show_help() {
cat << EOF
Usage: ${0##*/} [-?] <NAME>
List information about docker hosts
  NAME          name of the new Web server
EOF
}

# Ask a question and provide a default answer
# Sets the variable to the answer or the default value
# 1:varname 2:question 3:default value
function ask() {
  echo -n "${2}: [$3] "
  read pp
  if [ "$pp" == "" ]; then
    eval ${1}=$3
  else
    eval ${1}=$pp
  fi
}

# Ask a yes/no question, returns true on answering y
# 1:question 2:default answer
function askif() {
  ask ypp "$1" "$2"
  [ "$ypp" == "y" ]
}

if [ "$1" == "" ]; then
  show_help
  exit 0
fi

echo "Checking requirements..."

if [ ! -x /usr/bin/docker ]; then
  echo "ERROR: Docker is not installed."
  exit 2
else
  echo Docker found at /usr/bin/docker.
fi

if [ ! -d /etc/nginx/conf.d ]; then
  echo "ERROR: Nginx server (Web proxy) is not installed."
  exit 2
else
  echo "Nginx config dir found at /etc/nginx/conf.d/"
fi

# check for known docker dns resolver
dockerdns=$(docker ps -q --filter "ancestor=mgood/resolvable")
if [ "$dockerdns" == "" ]; then
  echo "WARNING: no known DNS resolver found for docker container names (*.docker)."
  if askif "Do you have a working DNS resolver for docker image names?" "n"; then
     ask ddnsname "Specify its docker name" "dresolver"
  else
    if askif "Install mgood/resolvable as DNS resolver?" "y"; then
       ask ddnsname "Short name for the DNS resolver container" "dresolver"
       docker create --name $ddnsname -v /var/run/docker.sock:/tmp/docker.sock -v /etc/resolv.conf:/tmp/resolv.conf mgood/resolvable || exit 1
       docker start $ddnsname ||  exit 1
    fi
  fi
else
  ddnsname=$(docker inspect --format "{{.Name}}" $dockerdns)
  echo "DNS resolver container name: $ddnsname"
fi
# try again
dockerdns=$(docker ps -q --filter "name=$ddnsname")
if [ "$dockerdns" == "" ]; then
  echo "WARNING: no working DNS resolver found. The Nginx proxy may not work."
else
  echo -n "DNS resolver status: "
  docker inspect --format "{{.State.Status}}" $ddnsname
fi

wname=$1

echo "Gathering information about the application..."
ask wdir "Directory that holds the server files" "/project/$wname"
if [ ! -d $wdir ]; then
  if askif "$wdir does not exists. Create?" "y"; then
    mkdir -p $wdir
  else
    echo "Exiting..."
    exit 1
  fi
fi
wwebdir="${wdir}/web"
echo "$wwebdir will hold the application server files (e.g. PHP code)."

ask wwebsrv "Docker image for running the Web app" "bitnami/php-fpm"
ask wwebsrvdir "Web (data) directory in the container" "/app"
echo "This directory will be linked to $wwebdir"

if askif "Do you need database for the server?" "n"; then
  wdbdir="${wdir}/db"
  ask wdbsrv "Docker image for DB" "bitnami/mariadb:latest"
  ask wdbsrvname "Short name of the server (role)" "dbserver"
  echo "This image will be linked to $wwebsrv as '$wdbsrvname'"
  ask wdbsrvdir "DB directory in the container" "/bitnami/mariadb"
  echo "This directory will be linked to $wdbdir"
else
  wdbsrv=""
  wdbdir="<none>"
  wdbsrvname="<none>"
  wdbsrvdir=""
fi

if askif "Do you need any additional docker server?" "n"; then
  ask waddsrv "Docker image name" "bitnami/mongodb:latest"
  ask waddsrvname "Short name of the server (role)" "mongodb"
  wadddir="${wdir}/${waddsrvname}"
  echo "This image will be linked to $wwebsrv as '$waddsrvname'"
  ask waddsrvdir "Data directory in the container" "/bitnami/mongodb"
  echo "This directory will be linked to $wadddir"
else
  waddsrv=""
  wadddir=""
  waddsrvname="<none>"
  waddsrvdir=""
fi

cat - << EOF

Configuration summary:
----------------------
Project name:  $wname
Project dir:   $wdir
Database dir:  $wdbdir
Web files:     $wwebdir
Docker images: $wwebsrv $wdbsrv $waddsrv
DNS resolver:  $ddnsname

EOF

if askif "Start the show?" "n"; then
  echo "Starting..."
else
  echo "OK. Stopping now."
  exit 0
fi

echo "Creating directories..."
echo "-----------------------"
echo mkdir -p $wdbdir $wwebdir
mkdir -p $wdbdir $wwebdir

echo "Setting up docker containers..."
linking=""
names=""
if [ "$wdbsrv" != "" ]; then
  echo "database..."
  docker create --name ${wname}-${wdbsrvname} -v ${wdbdir}:${wdbsrvdir} $wdbsrv || exit 1
  linking="$linking --link ${wname}-${wdbsrvname}:${wdbsrvname}"
  names="$names ${wname}-${wdbsrvname}"
fi
if [ "$waddsrv" != "" ]; then
  echo "${waddsrvname}..."
  docker create --name ${wname}-${waddsrvname} -v ${wadddir}:${waddsrvdir} $waddsrv || exit 1
  linking="$linking --link ${wname}-${waddsrvname}:${waddsrvname}"
  names="$names ${wname}-${waddsrvname}"
fi

docker create --name $wname $linking -v ${wwebdir}:${wwebsrvdir} ${wwebsrv} || exit 1
names="$names $wname"

cat - <<EOF
The containers are ready.
You can start and stop the container(s) by issuing
  docker start $names
  docker stop $names
You should check the owner/premission requirements of the shared app folder.
E.g. php-fpm requires 'daemon' in the container ('bin' on the CentOS host)

EOF

if askif "Do you want to start them now?" "n"; then
  docker start $names || exit 1
fi


if askif "Do you want to setup a vhost-based nginx proxy to ${wname}?" "n"; then
  ask wurl "Public (external) name" "${wname}.mit.bme.hu"
  if [ -f /etc/nginx/conf.d/${wname}.conf ]; then
    echo "WARNING: /etc/nginx/conf.d/${wname}.conf exists, not willing to overwrite."
  else
    cat - <<EOF >> /etc/nginx/conf.d/${wname}.conf
server {
  listen 80;

  server_name $wurl;

  root ${wwebdir};

  access_log            /var/log/nginx/${wname}.access.log;

# All requests are handled by the ${wname} docker server
  location / {
    root /$wwebsrvdir;
    proxy_set_header        Host \$host;
    proxy_set_header        X-Real-IP \$remote_addr;
    proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header        X-Forwarded-Proto \$scheme;
    proxy_pass          http://${wname}.docker;
    proxy_read_timeout  90;
    proxy_redirect      http://${wname}.docker http://$wurl;
  }

# PHP scripts are served using the docker image
  location ~ \.php$ {
        fastcgi_pass ${wname}.docker:9000;
        root /$wwebsrvdir;
        fastcgi_index index.php;
        include fastcgi.conf;
    }

#  location / {
#    index index.php;
#  }

}

EOF
    echo "/etc/nginx/conf.d/${wname}.conf created. You should review its content."
    echo "You need to decide what is handled by the docker image."
    echo "Restart nginx to activate the new proxy vhost."
  fi
fi

# TODO letsencrypt certbot....
# https://github.com/JrCs/docker-letsencrypt-nginx-proxy-companion
# https://www.digitalocean.com/community/tutorials/how-to-secure-nginx-with-let-s-encrypt-on-centos-7

# TODO systemd init fájl
#  cd /etc/systemd/system/
#  wget https://raw.githubusercontent.com/coeusite/docker-startup-systemd/master/docker-startup%40.service
#  systemctl daemon-reload
#  systemctl enable docker-startup@dresolver.service
#  systemctl start docker-startup@dresolver.service
