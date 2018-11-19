FROM robertcsmith/base1.1-alpine3.8-docker

LABEL robertcsmith.redis.namespace="robertcsmith/" \
	robertcsmith.redis.name="redis" \
	robertcsmith.redis.release="4.0.11" \
	robertcsmith.redis.flavor="-alpine3.8" \
	robertcsmith.redis.version="-docker" \
	robertcsmith.redis.tag=":1.0, :latest" \
	robertcsmith.redis.image="robertcsmith/redis4.0.11-alpine3.8-docker:1.0" \
	robertcsmith.redis.vcs-url="https://github.com/robertcsmith/redis4.0.11-alpine3.8-docker" \
	robertcsmith.redis.maintainer="Robert C Smith <robertchristophersmith@gmail.com>" \
	robertcsmith.redis.usage="README.md" \
	robertcsmith.redis.description="This image can be used to create a compatible Redis container \
		for to store session data or as a back-end, non-volitile memory caching service."

ENV REDIS_VERSION="4.0.11"
ENV REDIS_DOWNLOAD_URL="http://download.redis.io/releases/redis-${REDIS_VERSION}.tar.gz" \
	REDIS_SHA256="fc53e73ae7586bcdacb4b63875d1ff04f68c5474c1ddeda78f00e5ae2eed1bbb" \
	REDIS_GROUP_ID="1982"

# Always consistently assign new group IDs.Then add them to the "app" user,
# regardless of dependencies subsequenyly added while keeping in mind the "app"
# user already belongs to the primary "root" and secondary "app" groups
RUN set -ex; \
	# Before anything takes place we update and/or upgrade the index for our apk tool
	apk update && apk upgrade; \
	# Create the secondary system group called "redis"
	addgroup -S -g $REDIS_GROUP_ID redis; \
	# Aassign the newly created secondary "redis" group to the "app" user
	addgroup app redis;

# Copy the local script base-pkg-mgr.sh to /usr/local/bin/base-pkg-mgr while setting its ownership
COPY --chown=app:root files/docker-entrypoint.sh /usr/local/bin/docker-entrypoint

RUN set -ex; \
	# grab su-exec for easy step-down from root
	apk add --no-cache 'su-exec>=0.2'; \
	# build deps
	apk add --no-cache --virtual .build-deps gcc jemalloc-dev; \
	# Fetch redis
	mkdir -p /usr/src/redis && cd /usr/src && wget -O redis.tar.gz $REDIS_DOWNLOAD_URL; \
	# Begin to test the tarball and files to ensure they are safe
	echo "${REDIS_SHA256} *redis.tar.gz" | sha256sum -c -; \
	tar -xzf /usr/src/redis.tar.gz -C /usr/src/redis --strip-components=1; \
	# Disable Redis protected mode [1] as it is unnecessary in context of Docker
	# (ports are not automatically exposed when running inside Docker, but rather explicitly by specifying -p / -P)
	# [1]: https://github.com/antirez/redis/commit/edd4d555df57dc84265fdfb4ef59a4678832f6da
	grep -q '^#define CONFIG_DEFAULT_PROTECTED_MODE 1$' /usr/src/redis/src/server.h; \
	sed -ri 's!^(#define CONFIG_DEFAULT_PROTECTED_MODE) 1$!\1 0!' /usr/src/redis/src/server.h; \
	grep -q '^#define CONFIG_DEFAULT_PROTECTED_MODE 0$' /usr/src/redis/src/server.h; \
	# for future reference, we modify this directly in the source instead of just supplying a default configuration
	# flag because apparently "if you specify any argument to redis-server, [it assumes] you are going to specify everything"
	# see also https://github.com/docker-library/redis/issues/4#issuecomment-50780840
	# (more exactly, this makes sure the default behavior of "save on SIGTERM" stays functional by default)
	make -C /usr/src/redis -j"$(nproc)" && make -C /usr/src/redis install; \
	# Set permissions on volume /data
	mkdir -p /data 2>/dev/null; \
	chown -R app:root /data redis-server && chmod -R 0775 /data redis-server /usr/local/bin/docker-entrypoint; \
	# Runtime deps
	redisRundeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
		| tr ',' '\n' \
		| sort -u \
		| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)"; \
	apk add --no-cache --virtual .redis-rundeps $redisRundeps; \
	# Cleanup
	apk del .build-deps; \
	rm -rf /usr/src/redis.tar.gz /usr/src/redis; \
	source base-pkg-mgr --uninstall; \
	redis-server --version | echo;

# when using multiple images these ports should be made different to avoid confusion and to
# to ensure the app uses the correct container
ENV	REDIS_EXPOSED_PORT="6379"

EXPOSE $REDIS_EXPOSED_PORT

USER app:root

WORKDIR /data

ENTRYPOINT [ "docker-entrypoint" ]

CMD [ "/bin/bash" ]
