# docker-helpers
Helper scripts for managing docker-based setups

## CreateWeb.sh
This scripts pulls and starts docker containers to serve as backends behind an nginx proxy server:
- a dns resolver (mgood/resolvable) that enables the usage of host names to identify containers
- an optional database server (e.g. mariadb)
- a web backend (e.g. php-fpm) that is also linked to the db container

The scripts uses a directory on the master host to provide persistence for data files within the containers (including databases and configurations).
It also tries to configure the nginx front end that probably won't be perfect in most cases but it is a good starting point.

## DockerInfo.sh
A simple helper to get various info (like IP address, name, hostname and status) about containers.

## docker-container.service
A systemd template unit to start/stop named containers.  
- Installation: save the unit file into /etc/systemd/system, then execute  
  <code>systemctl daemon-reload</code>
- Create a unit for a container named "foo" and start it upon boot:  
  <code>systemctl enable docker-container@foo.service</code>
- Start the container:  
  <code>systemctl start docker-container@foo.service</code>
- Stop the container:  
  <code>systemctl stop docker-container@foo.service</code>
- Verify the container:  
  <code>systemctl status docker-container@foo.service</code>
