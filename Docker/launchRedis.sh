#!/bin/bash

function search_and_replace() {
  search=$(echo $1 | sed 's;/;\\/;g')
  replace=$(echo $2 | sed 's;/;\\/;g')
  sed -i "s/$search/$replace/g" $3
}

function set_password() {
  # get REDIS_PASSWORD from env if not set to default
  if [ "${REDIS_PASSWORD}" == "" ]; then
    echo "setting default password.."
    REDIS_PASSWORD="redispassword"
  fi

  export REDIS_PASSWORD=${REDIS_PASSWORD}
}

#  This method launches sentinels
function launch_sentinel() {
  echo "Starting Sentinel.."
  sleep_for_rand_int=$(awk -v min=2 -v max=7 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')
  sleep ${sleep_for_rand_int}

  set_password

  while true; do
    echo "Connecting to Sentinel Service..."

    master=$(redis-cli -h ${SERVICE} -p ${SENTINEL_PORT} --csv SENTINEL get-master-addr-by-name ${MASTER_NAME} | tr ',' ' ' | cut -d' ' -f1)
    if [[ -n ${master} ]]; then
      echo "Connected to Sentinel Service and retrieved Redis Master IP as ${master}"
      master="${master//\"/}"
    else
      REDIS_HA_0=$(getent hosts "$SERVICE-0" | awk '{ print $1 }')
      echo "Unable to connect to Sentinel Service, probably this is the first Sentinel to start, marking ${REDIS_HA_0} as ${MASTER_NAME}..."
      master=${REDIS_HA_0}

      if [[ -n ${master} ]]; then
        echo "Retrieved Redis Master IP as ${master}"
        break
      else
        echo "Unable to retrieve Master IP from the redis service. Waiting..."
        sleep 10
        continue
      fi
    fi

  done

  mkdir -p ${CONFIG_ROOT}
  echo "sentinel monitor ${MASTER_NAME} ${master} 6379 2" >${SENTINEL_CONF}
  echo "sentinel down-after-milliseconds ${MASTER_NAME} 5000" >>${SENTINEL_CONF}
  echo "sentinel failover-timeout ${MASTER_NAME} 60000" >>${SENTINEL_CONF}
  echo "sentinel parallel-syncs ${MASTER_NAME} 1" >>${SENTINEL_CONF}
  echo "bind 0.0.0.0" >>${SENTINEL_CONF}
  echo "sentinel auth-pass ${MASTER_NAME} ${REDIS_PASSWORD}" >>${SENTINEL_CONF}

  redis-sentinel ${SENTINEL_CONF} --protected-mode no
}

#  This method launches redis servers
function launch_server() {
  echo "Starting Redis instance"

  set_password

  if [ "$INDEX" = "0" ]; then
    echo "Setting this pod as the default master"
    sed -i '/slaveof/d' ${REDIS_CONF}
  fi

  while true; do
    echo "Trying to retrieve the Master IP again, in case of failover master ip would have changed."
    master=$(redis-cli -h ${SERVICE} -p ${SENTINEL_PORT} --csv SENTINEL get-master-addr-by-name ${MASTER_NAME} | tr ',' ' ' | cut -d' ' -f1)
    if [[ -n ${master} ]]; then
      master="${master//\"/}"
      break
    else
      echo "Failed to find master."
      sleep 20
      continue
    fi
    redis-cli -a ${REDIS_PASSWORD} -h ${master} INFO
    if [[ "$?" == "0" ]]; then
      break
    fi
    echo "Connection to master not established, sleeping..."
    sleep 10
  done

  search_and_replace %master-ip% ${master} ${REDIS_CONF}
  search_and_replace %master-port% ${REDIS_PORT} ${REDIS_CONF}
  search_and_replace %data-dir% ${DATA_ROOT} ${REDIS_CONF}
  search_and_replace %redis-password% ${REDIS_PASSWORD} ${REDIS_CONF}

  redis-server ${REDIS_CONF} --protected-mode no
}

#  This method launches redis ha
function launchredis() {
  echo "Launching Redis instance"

  mkdir -p ${CONFIG_ROOT}
  mkdir -p ${DATA_ROOT}

  cp ${REDIS_CONF_TEMPLATE} ${REDIS_CONF}

  launch_server
}

SERVICE=redis-ha
HOSTNAME="$(hostname)"
INDEX="${HOSTNAME##*-}"

REDIS_PORT=6379
SENTINEL_PORT=26379

ROOT=/redis-ha/redis-data/$INDEX
CONFIG_ROOT=$ROOT/conf
DATA_ROOT=$ROOT/data

REDIS_CONF_TEMPLATE=/redis-ha/templates/redis.conf
REDIS_CONF=$CONFIG_ROOT/redis.conf
SENTINEL_CONF=$CONFIG_ROOT/sentinel.conf

MASTER_NAME="mymaster"

if [[ "${SENTINEL}" == "true" ]]; then
  launch_sentinel
  exit 0
fi

launchredis
