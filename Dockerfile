# python: 3.11.2
# pgadmin: 6.20.0
FROM python:3.11.2-alpine3.16 AS builder
#  alpine3.16 uses openss1.1.1  https://github.com/pyca/cryptography/issues/7868 , alpine 3.17 uses openssl 3.0.x that
#   raises ImportError with FIPS_mode
MAINTAINER Gabriele Pongelli <gabriele.pongelli@gmail.com>

ENV PGADMIN_VERSION=6.20
ENV PYTHONDONTWRITEBYTECODE=1
ENV CRYPTOGRAPHY_DONT_BUILD_RUST=1

# use piwheels to avoid building wheels
RUN echo "[global]" > /etc/pip.conf \
    && echo "extra-index-url=https://www.piwheels.org/simple" >> /etc/pip.conf

# install packages to compile pillow and the other python packages on ARM
RUN apk add --no-cache \
        fribidi-dev \
        freetype-dev \
        harfbuzz-dev \
        lcms2-dev \
        libedit \
        libffi-dev \
        libimagequant-dev \
        libpng-dev \
        libwebp-dev \
        libxcb-dev \
        jpeg-dev \
        openjpeg-dev \
        postgresql-dev \
        tcl-dev \
        tiff-dev \
        tk-dev \
        zlib-dev

# dnspython==2.3.0 has issue with eventlet==0.33.0 (pgadmin4 has pinned eventlet version)
#  https://github.com/eventlet/eventlet/issues/781   https://github.com/pgadmin-org/pgadmin4/issues/5744
RUN apk add --no-cache alpine-sdk linux-headers \
 && pip install --upgrade pip \
 && pip install --no-cache-dir --upgrade Flask-WTF>=0.14.3 \
 && pip install --no-cache-dir Werkzeug>=2.2.2 simple-websocket dnspython==2.2.1 \
 && echo "https://ftp.postgresql.org/pub/pgadmin/pgadmin4/v${PGADMIN_VERSION}/pip/pgadmin4-6.20-py3-none-any.whl" | pip install --no-cache-dir -r /dev/stdin \
 && apk del alpine-sdk linux-headers

##
## -------------------------------------------
##

FROM python:3.11.2-alpine3.16 AS gosu_builder
MAINTAINER Gabriele Pongelli <gabriele.pongelli@gmail.com>

# switch to root, let the entrypoint drop back to pgadmin4
USER root

ENV GOSU_VERSION 1.16
RUN set -eux; \
	\
	apk add --no-cache --virtual .gosu-deps \
		ca-certificates \
		dpkg \
		dirmngr \
		gnupg \
	; \
	\
	dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
	wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
	wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
	\
# verify the signature
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
	gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
	command -v gpgconf && gpgconf --kill all || :; \
	rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
	\
# clean up fetch dependencies
	apk del --no-network .gosu-deps; \
	\
	chmod +x /usr/local/bin/gosu; \
# verify that the binary works
	gosu --version; \
	gosu nobody true


##
## -------------------------------------------
##

FROM python:3.11.2-alpine3.16 AS app
MAINTAINER Gabriele Pongelli <gabriele.pongelli@gmail.com>

# switch to root, let the entrypoint drop back to pgadmin4
USER root

# create a non-privileged user to use at runtime, install non-devel packages
RUN addgroup -g 50 -S pgadmin4 \
 && adduser -D -S -h /pgadmin4 -s /sbin/nologin -u 1000 -G pgadmin4 pgadmin4 \
 && mkdir -p /pgadmin4/config /pgadmin4/storage \
 && chown -R pgadmin4:pgadmin4 /pgadmin4 \
 && chmod -R g+rwX /pgadmin4 \
 && addgroup pgadmin4 tty \
 && apk add \
    fribidi \
    freetype \
    harfbuzz \
    lcms2 \
    libc6-compat \
    libedit \
    libffi \
    libimagequant \
    libpng \
    libpq \
    libstdc++ \
    libwebp \
    libxcb \
    jpeg \
    openjpeg \
    postgresql \
    tcl \
    tiff \
    tk \
    zlib

EXPOSE 5050

# add an entry-point script
ENV ENTRY_POINT="entrypoint.sh"
COPY ${ENTRY_POINT} /${ENTRY_POINT}
RUN chmod 755 /${ENTRY_POINT}
ENV ENTRY_POINT=

# copy from builder image
COPY --from=builder /usr/local/lib/python3.11/  /usr/local/lib/python3.11/

# copy gosu from other image
COPY --from=gosu_builder /usr/local/bin/gosu  /usr/local/bin/gosu
RUN chmod +x /usr/local/bin/gosu;

# copy from local folder
COPY LICENSE config_distro.py /usr/local/lib/python3.11/site-packages/pgadmin4/

WORKDIR /pgadmin4
VOLUME /pgadmin4

# run entrypoint as root, gosu will change
#USER pgadmin4

# using exec form to run also CMD into the entrypoint.
# shell form will ignore CMD or docker run command line arguments
# ref https://docs.docker.com/engine/reference/builder/#shell-form-entrypoint-example
ENTRYPOINT ["/entrypoint.sh"]

# https://docs.docker.com/engine/reference/builder/#understand-how-cmd-and-entrypoint-interact
# the exec form works correctly when launching with user: 0 and without it
# the shell form does starting loop if launched as pgadmin4 user
CMD ["python", "/usr/local/lib/python3.11/site-packages/pgadmin4/pgAdmin4.py"]
