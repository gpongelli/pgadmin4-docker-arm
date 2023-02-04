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
    # folder absent
    if [ ! -d "$HOME"/config ]; then
        mkdir -p $HOME/config
    fi

    # folder absent
    if [ ! -d "$HOME"/storage ]; then
        mkdir -p $HOME/storage
    fi

    chown -Rc "$PUID:$PGID" "$HOME"

    # Add call to gosu to drop from root user to pgadmin4 user
    exec gosu pgadmin4 "$@"
fi

exec $@
