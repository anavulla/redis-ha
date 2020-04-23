FROM redis:latest

RUN apt-get install bash \
    sed

RUN mkdir /redis-ha
WORKDIR /redis-ha

COPY redis.conf /redis-ha/templates/redis.conf
COPY launchRedis.sh /redis-ha/scripts/launchRedis.sh

RUN chmod 777 /redis-ha/scripts/launchRedis.sh

CMD [ "/redis-ha/scripts/launchRedis.sh" ]

ENTRYPOINT [ "bash", "-c" ]
