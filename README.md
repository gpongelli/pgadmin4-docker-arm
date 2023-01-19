[![Pulls](https://img.shields.io/docker/pulls/gpongelli/pgadmin4-docker-armv7.svg?style=flat-square&logo=docker)](https://hub.docker.com/r/gpongelli/pgadmin4-docker-armv7/)
[![DockerBuild](https://img.shields.io/docker/cloud/build/gpongelli/pgadmin4-docker-armv7.svg?style=flat-square&logo=docker)](https://hub.docker.com/r/gpongelli/pgadmin4-docker-armv7/)


Last updated by bot: 2023-01-19

# pgAdmin 4

This is a simple Raspberry Docker image for running pgAdmin 4 in a container. The default
configuration is not intended for production use (it runs in "desktop mode",
so authentication is disabled).

This image uses an unprivileged user, and uses port `5050` instead of `80`.
To access the web-interface on port `80` instead of `5050`, you can map the
port using `-p 80:5050`.

## Fix issue of Docker on Mac OSX

Sometimes happens that Docker on Mack hangs at startup, an useful list of command to fix is:

```bash
rm -rf ~/Library/Containers/com.docker.*
cd /usr/local/bin
chmod 0755 dock*
```

## Original credits 

Credits for the starting structure of this project goes to [FlorianASchroeder](https://github.com/FlorianASchroeder/pgadmin4-docker).

Starting from that project, I've added the github actions to build docker image for Raspberry's armv7 architecture.


## Tags
To use a specific combination of pgAdmin 4 and python see the following table of available image tags.

|       Tag       |  pgAdmin version  |  Python version  |   Distro   |  Architecture  |
|-----------------|-------------------|------------------|------------|----------------|
|  `6.19-py3.11`  |       6.19        |      3.11.1      | alpine3.16 |     armv7      |

Lovely! These tags are kept updated automatically (when new minor or patch version are released) by `build_versions.py` which is run twice a day on CircleCI.

## Example use

### Quick start

To see this image in action, run the following command;

```bash
$ docker run --rm -p 5050:5050 thajeztah/pgadmin4
```

This starts a one-off container in non-detached mode, and container logs are
printed in your terminal. After the container has finished starting, visit
`http://[your-docker-host]:5050` in your browser to try pgAdmin 4.

To exit and remove the container, press `CTRL+C` in your terminal.


### Practical example

This example uses a custom network, and runs a PostgreSQL container.

```bash
# create a custom network for easier connecting
$ docker network create pg

# start a postgres container
$ docker run -d -e POSTGRES_PASSWORD=password --network=pg --name postgres postgres:9-alpine

# start pgAdmin container
$ docker run -d -p 5050:5050 --name pgadmin --network=pg thajeztah/pgadmin4
```

Now visit `http://[your-docker-host]:5050` in your browser. You can add the
postgres database (hostname is `postgres`, password is `password`) to test
if everything is working.

![screenshot](https://raw.githubusercontent.com/thaJeztah/pgadmin4-docker/master/pgadmin-screenshot.png)

## Persistent data

Persistent data is stored in a volume, located at `/pgadmin/`. This allows
you to upgrade the container to a new version without losing configuration.

The following directories can be found inside the volume;

- `/pgadmin/config/pgadmin4.db` - SQLite configuration database
- `/pgadmin/storage/` - other storage

You can override the storage location using the `PG_ADMIN_DATA_DIR`
environment variable

## Unprivileged user

pgAdmin runs as an unprivileged user (`pgadmin`) with `uid:gid` `1000:50`.
The `uid:gid` is selected for compatibility with Docker Toolbox, and allows
you to bind-mount a local directory inside the container for persistent
storage

For example, to bind-mount the `/Users/me/pgadmin` directory as storage directory;

```bash
$ docker run -d -p 5050:5050 -v /Users/me/pgadmin:/pgadmin thajeztah/pgadmin4
```

## Run the image with a read-only filesystem

This image can be run with a read-only filesystem. To do so, specify the
`--read-only` flag when starting the container.

```bash
$ docker run -d -p 5050:5050 --name pgadmin --read-only thajeztah/pgadmin4
```

## Runtime configuration

This image can be configured at runtime, by setting environment variables;

- `PG_ADMIN_DATA_DIR` directory to use for storing data (defaults to `/pgadmin/`)
- `PG_ADMIN_PORT` port to listen on (defaults to `5050`)
- `PG_ADMIN_SESSION_DIR` directory to use for storing server-side sessions (defaults to `/dev/shm/pgAdmin4_session`)
- `DEBUG` enable debug mode (detaults to `False`)

More information on pgAdmin 4 development can be found here;

- https://git.postgresql.org/gitweb/?p=pgadmin4.git;a=summary
- https://www.pgadmin.org

## Reporting issues and feature requests

Issues and feature requests can be reported on GitHub;
https://github.com/thaJeztah/pgadmin4-docker
