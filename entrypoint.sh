#!/bin/ash
set -e -x

export HOME=/pgadmin4

# ref https://docs.docker.com/engine/reference/builder/#entrypoint
# trap "echo TRAPed signal" HUP INT QUIT TERM


# can be overridden in the service definition, 1000 and 50 comes from Dockerfile
PUID=${PUID:-1000}
PGID=${PGID:-50}

# enforce ownership if running as root
user="$(id -u)"
if [ "$user" = '0' ]; then
    # https://github.com/sudo-bmitch/jenkins-docker/blob/main/entrypoint.sh
    # get gid of docker socket file
    SOCK_DOCKER_GID=`ls -ng /var/run/docker.sock | cut -f3 -d' '`

    # get group of docker inside container
    CUR_DOCKER_GID=`getent group docker | cut -f3 -d: || true`

    # if they don't match, adjust
    if [ ! -z "$SOCK_DOCKER_GID" -a "$SOCK_DOCKER_GID" != "$CUR_DOCKER_GID" ]; then
        groupmod -g ${SOCK_DOCKER_GID} -o docker
    fi
    if ! groups pgadmin4 | grep -q docker; then
        usermod -aG docker pgadmin4
    fi

    # $HOME folder absent
    if [ ! -d "$HOME" ]; then
        mkdir -p $HOME/config $HOME/storage
    fi
    chown -Rc "$PUID:$PGID" "$HOME"

    # Add call to gosu to drop from root user to pgadmin4 user
    exec gosu pgadmin4 "$@"
fi

exec $@
