#!/bin/ash
set -e -x

export HOME=/pgadmin4

# ref https://docs.docker.com/engine/reference/builder/#entrypoint
#trap "echo TRAPed signal" HUP INT QUIT TERM


# can be overridden in the service definition, 1000 and 50 comes from Dockerfile
PUID=${PUID:-1000}
PGID=${PGID:-50}

chown -R "$PUID:$PGID" "$HOME"

# beign able to write to /dev/stdout not only by root user
# https://github.com/moby/moby/issues/31243
chmod o+w /dev/stdout

# Add call to gosu to drop from root user to pgadmin4 user
exec gosu pgadmin4 "$@"
