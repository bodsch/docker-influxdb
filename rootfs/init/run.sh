#!/bin/sh

set -e
# set -x

if [ "${1:0:1}" = '-' ]
then
    set -- influxd "$@"
fi

if [ "$1" = 'influxd' ]
then
  /init/configure_influxdb.sh "${@:2}"
fi

exec "$@"
