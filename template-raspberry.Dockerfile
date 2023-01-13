# python: %%PYTHON_CANONICAL%%
# pgadmin: %%PGADMIN_CANONICAL%%
FROM python:%%PYTHON_IMAGE%%
MAINTAINER Gabriele Pongelli <gabriele.pongelli@gmail.com>

# create a non-privileged user to use at runtime
RUN addgroup -g 50 -S pgadmin \
 && adduser -D -S -h /pgadmin -s /sbin/nologin -u 1000 -G pgadmin pgadmin \
 && mkdir -p /pgadmin/config /pgadmin/storage /var/log/pgadmin /var/lib/pgadmin \
 && chown -R 1000:50 /pgadmin \
 && chown -R 1000:50 /var/log/pgadmin \
 && chown -R 1000:50 /var/lib/pgadmin

# Install postgresql tools for backup/restore
RUN apk add --no-cache libedit postgresql \
 && cp /usr/bin/psql /usr/bin/pg_dump /usr/bin/pg_dumpall /usr/bin/pg_restore /usr/local/bin/ \
 && apk del postgresql

# Install packages to compile pillow on arm
RUN apk add tiff-dev jpeg-dev openjpeg-dev zlib-dev freetype-dev lcms2-dev \
    libwebp-dev tcl-dev tk-dev harfbuzz-dev fribidi-dev libimagequant-dev \
    libxcb-dev libpng-dev

RUN apk add --no-cache postgresql-dev libffi-dev

ENV PGADMIN_VERSION=%%PGADMIN%%
ENV PYTHONDONTWRITEBYTECODE=1
ENV CRYPTOGRAPHY_DONT_BUILD_RUST=1

RUN apk add --no-cache alpine-sdk linux-headers \
 && pip install --upgrade pip \
 && echo "https://ftp.postgresql.org/pub/pgadmin/pgadmin4/v${PGADMIN_VERSION}/pip/%%PGADMIN_WHL%%" | pip install --no-cache-dir -r /dev/stdin \
 && pip install --no-cache-dir --upgrade Flask-WTF>=0.14.3 \
 && apk del alpine-sdk linux-headers

EXPOSE 5050

COPY LICENSE config_distro.py /usr/local/lib/python%%PYTHON%%/site-packages/pgadmin4/

USER pgadmin:pgadmin
CMD ["python", "./usr/local/lib/python%%PYTHON%%/site-packages/pgadmin4/pgAdmin4.py"]
VOLUME /pgadmin/
