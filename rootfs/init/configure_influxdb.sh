#!/bin/bash

# set -x
set -e

INFLUXDB_INIT_PORT="8086"
PID=
INFLUXDB_ADMIN_USER="admin"

INFLUX_CMD="influx -host 127.0.0.1 -port ${INFLUXDB_INIT_PORT} -execute "


AUTH_ENABLED="${INFLUXDB_HTTP_AUTH_ENABLED}"

if [ -z "${AUTH_ENABLED}" ]; then
  AUTH_ENABLED="$(grep -iE '^\s*auth-enabled\s*=\s*true' /etc/influxdb/influxdb.conf | grep -io 'true' | cat)"
else
  AUTH_ENABLED="$(echo ""${INFLUXDB_HTTP_AUTH_ENABLED}"" | grep -io 'true' | cat)"
fi

INIT_USERS=$([ ! -z "${AUTH_ENABLED}" ] && [ ! -z "${INFLUXDB_ADMIN_USER}" ] && echo 1 || echo)


start_influx() {

  INFLUXDB_HTTP_BIND_ADDRESS=127.0.0.1:${INFLUXDB_INIT_PORT} influxd 2> /dev/null "$@" &
  PID="$!"
}

stop_influx() {

  if ! kill -s TERM "${PID}" || ! wait "${PID}"
  then
    echo >&2 ' [E] influxdb init process failed. (Could not stop influxdb)'
    exit 1
  fi
}


create_database() {

  local database=${1}
  local retention_policy=${2}

  local query="CREATE DATABASE ${database}"

  if [ ! -z ${retention_policy} ]
  then
    query="${query} WITH DURATION ${retention_policy}"
  fi

  ${INFLUX_CMD} "${query}"
  # ${INFLUX_CMD} "SHOW RETENTION POLICIES ON ${database}"
}

create_user() {

  local user=${1}
  local password=${2}
  local database=${3} # not yet supported
  local rights=${4}   # not yet supported

  query="SHOW USERS"

  if [ $(${INFLUX_CMD} "${query}" 2> /dev/null | grep -c "^${user}") -eq 0 ]
  then
    echo "     - ${user}"

    local influx_cmd="influx -host 127.0.0.1 -port ${INFLUXDB_INIT_PORT} -username ${INFLUXDB_ADMIN_USER} -password ${INFLUXDB_ADMIN_PASSWORD} -execute "

    ${influx_cmd} "CREATE USER ${user} WITH PASSWORD '${password}'"

    ${influx_cmd} "REVOKE ALL PRIVILEGES FROM ""${user}"""

    if [ ! -z "${database}" ]
    then
      ${influx_cmd} "GRANT ALL ON ""${database}"" TO ""${user}"""
    fi

  fi
}


init() {

  for i in {30..0}
  do
    if ${INFLUX_CMD} "SHOW DATABASES" &> /dev/null
    then
      break
    fi
    echo ' [i] influxdb init process in progress...'
    sleep 1
  done

  if [ "$i" = 0 ]
  then
    echo >&2 ' [E] influxdb init process failed.'
    exit 1
  fi

  databases=$(echo "${DATABASES}"  | jq '.')

  if [ ! -z "${databases}" ]
  then
    echo " [i] create InfluxDB databases"

    echo "${databases}" | jq --compact-output --raw-output '.[]' | while IFS='' read u
    do
      name=$(echo "${u}" | jq --raw-output .name)
      retention_policy=$(echo "${u}" | jq --raw-output .retention_policy)

      [ ${retention_policy} == null ] && retention_policy=

      create_database "${name}" "${retention_policy}"
    done
  fi

  users=$(echo "${USERS}"  | jq '.')

  if [ ! -z "${users}" ]
  then
    echo " [i] create InfluxDB users"

    query="SHOW USERS"

    if [ $(${INFLUX_CMD} "${query}" 2> /dev/null | grep -c "^admin") -eq 0 ]
    then

      if [ -z "${INFLUXDB_ADMIN_PASSWORD}" ]
      then
        INFLUXDB_ADMIN_PASSWORD="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32;echo;)"
        echo " [i] INFLUXDB_ADMIN_PASSWORD: ${INFLUXDB_ADMIN_PASSWORD}"
      fi

      query="CREATE USER ${INFLUXDB_ADMIN_USER} WITH PASSWORD '${INFLUXDB_ADMIN_PASSWORD}' WITH ALL PRIVILEGES"
      ${INFLUX_CMD} "${query}"

      echo ${INFLUXDB_ADMIN_PASSWORD} > /srv/influxdb/password
    else
      INFLUXDB_ADMIN_PASSWORD=$(cat /srv/influxdb/password)
    fi

    export INFLUXDB_ADMIN_USER
    export INFLUXDB_ADMIN_PASSWORD

    echo "${users}" | jq --compact-output --raw-output '.[]' | while IFS='' read u
    do
      user=$(echo "${u}" | jq --raw-output .user)
      password=$(echo "${u}" | jq --raw-output .password)
      database=$(echo "${u}" | jq --raw-output .database)
      rights=$(echo "${u}" | jq --compact-output --raw-output .rights)

      [ ${database} == null ] && database=
      [ ${rights} == null ] && rights=

      create_user "${user}" "${password}" "${database}" "${rights}"
    done
  fi
}


custom_config() {

  for f in /init/initdb.d/*
  do
    case "$f" in
      *.sh)     echo "$0: running $f"; . "$f" ;;
      *.iql)    echo "$0: running $f"; ${INFLUX_CMD} "$(cat ""$f"")"; echo ;;
      *)        echo "$0: ignoring $f" ;;
    esac
    echo
  done
}


# ---------------------------------

start_influx

init

custom_config

stop_influx
