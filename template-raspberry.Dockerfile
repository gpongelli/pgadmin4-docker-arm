# python: %%PYTHON_CANONICAL%%
# pgadmin: %%PGADMIN_CANONICAL%%
FROM python:%%PYTHON_IMAGE%% AS builder
#  alpine3.16 uses openss1.1.1  https://github.com/pyca/cryptography/issues/7868 , alpine 3.17 uses openssl 3.0.x that
#   raises ImportError with FIPS_mode
MAINTAINER Gabriele Pongelli <gabriele.pongelli@gmail.com>

ENV PGADMIN_VERSION=%%PGADMIN%%
ENV PYTHONDONTWRITEBYTECODE=1
ENV CRYPTOGRAPHY_DONT_BUILD_RUST=1

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
 && echo "https://ftp.postgresql.org/pub/pgadmin/pgadmin4/v${PGADMIN_VERSION}/pip/%%PGADMIN_WHL%%" | pip install --no-cache-dir -r /dev/stdin \
 && apk del alpine-sdk linux-headers

##
## -------------------------------------------
##

FROM python:%%PYTHON_IMAGE%% AS app
MAINTAINER Gabriele Pongelli <gabriele.pongelli@gmail.com>

# switch to root, let the entrypoint drop back to pgadmin4
USER root

# create a non-privileged user to use at runtime, install non-devel packages
RUN addgroup -g 50 -S pgadmin4 \
 && adduser -D -S -h /pgadmin4 -s /sbin/nologin -u 1000 -G pgadmin4 pgadmin4 \
 && mkdir -p /pgadmin4/config /pgadmin4/storage \
 && chown -R pgadmin4:pgadmin4 /pgadmin4 \
 && chmod -R g+rwX /pgadmin4 \
 && apk add \
    fribidi \
    freetype \
    harfbuzz \
    lcms2 \
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

# install gosu for a better su+exec command
RUN wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/%%GOSU_VERSION%%/gosu-%%GOSU_ARCH%%" \
 && chmod +x /usr/local/bin/gosu \
 && gosu nobody true

EXPOSE 5050

VOLUME /pgadmin4/

COPY --from=builder /usr/local/lib/python%%PYTHON%%/  /usr/local/lib/python%%PYTHON%%/

COPY LICENSE config_distro.py /usr/local/lib/python%%PYTHON%%/site-packages/pgadmin4/

# add an entry-point script
ENV ENTRY_POINT="entrypoint.sh"
COPY ${ENTRY_POINT} /${ENTRY_POINT}
RUN chmod 755 /${ENTRY_POINT}
ENV ENTRY_POINT=


# using exec form to run also CMD into the entrypoint.
# shell form will ignore CMD or docker run command line arguments
# ref https://docs.docker.com/engine/reference/builder/#shell-form-entrypoint-example
ENTRYPOINT ["/entrypoint.sh"]

# https://docs.docker.com/engine/reference/builder/#understand-how-cmd-and-entrypoint-interact
# shell form does variable expansion/substitution
CMD python /usr/local/lib/python%%PYTHON%%/site-packages/pgadmin4/pgAdmin4.py
