
FROM alpine:3.6

MAINTAINER Bodo Schulz <bodo@boone-schulz.de>

ENV \
  ALPINE_MIRROR="mirror1.hs-esslingen.de/pub/Mirrors" \
  ALPINE_VERSION="v3.6" \
  TERM=xterm \
  BUILD_DATE="2017-09-08" \
  INFLUXDB_VERSION="1.3.5"

EXPOSE 2003 8083 8086

LABEL \
  version="1709-36" \
  org.label-schema.build-date=${BUILD_DATE} \
  org.label-schema.name="InfluxDB Docker Image" \
  org.label-schema.description="Inofficial InfluxDB Docker Image" \
  org.label-schema.url="https://www.influxdb.com/" \
  org.label-schema.vcs-url="https://github.com/bodsch/docker-influxdb" \
  org.label-schema.vendor="Bodo Schulz" \
  org.label-schema.version=${INFLUXDB_VERSION} \
  org.label-schema.schema-version="1.0" \
  com.microscaling.docker.dockerfile="/Dockerfile" \
  com.microscaling.license="GNU General Public License v3.0"

# ---------------------------------------------------------------------------------------

COPY rootfs/ /

RUN \
  echo "http://${ALPINE_MIRROR}/alpine/${ALPINE_VERSION}/main"       > /etc/apk/repositories && \
  echo "http://${ALPINE_MIRROR}/alpine/${ALPINE_VERSION}/community" >> /etc/apk/repositories && \
  apk --no-cache update && \
  apk --no-cache upgrade && \
  echo 'hosts: files dns' >> /etc/nsswitch.conf && \
  apk add --no-cache tzdata bash && \
  set -e && \
  apk add --no-cache --virtual .build-deps wget gnupg tar ca-certificates && \
  update-ca-certificates 2> /dev/null && \
  for key in \
    05CE15085FC09D18E99EFB22684A14CF2582E0C5 ; \
  do \
    gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$key" || \
    gpg --keyserver pgp.mit.edu --recv-keys "$key" || \
    gpg --keyserver keyserver.pgp.com --recv-keys "$key" ; \
  done && \
  #
  wget -q https://dl.influxdata.com/influxdb/releases/influxdb-${INFLUXDB_VERSION}-static_linux_amd64.tar.gz.asc && \
  wget -q https://dl.influxdata.com/influxdb/releases/influxdb-${INFLUXDB_VERSION}-static_linux_amd64.tar.gz && \
  #
  gpg --batch --verify influxdb-${INFLUXDB_VERSION}-static_linux_amd64.tar.gz.asc influxdb-${INFLUXDB_VERSION}-static_linux_amd64.tar.gz && \
  #
  mkdir -p /usr/src && \
  tar -C /usr/src -xzf influxdb-${INFLUXDB_VERSION}-static_linux_amd64.tar.gz && \
  mv -v /usr/src/influxdb-*/influxdb.conf /etc/influxdb/influxdb.conf-DIST  && \
  chmod -v +x /usr/src/influxdb-*/influx* && \
  cp -av /usr/src/influxdb-*/influx* /usr/bin/ && \
  #
  apk del .build-deps && \
  rm -rf \
    /tmp/* \
    /usr/src \
    /root/.gnupg \
    /var/cache/apk/*

VOLUME [ "/var/lib/influxdb", "/srv" ]

ENTRYPOINT ["/init/run.sh"]

CMD ["influxd"]
