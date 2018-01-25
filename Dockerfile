FROM golang:1.10-rc-alpine
MAINTAINER Lars Gierth <lgierth@ipfs.io>

# There is a copy of this Dockerfile called Dockerfile.fast,
# which is optimized for build time, instead of image size.
#
# Please keep these two Dockerfiles in sync.

RUN apk -U add wget git make gcc musl-dev

RUN go get -v -u github.com/whyrusleeping/gx
RUN go get -v -u github.com/whyrusleeping/gx-go

ENV GX_IPFS ""
ENV SRC_DIR /go/src/github.com/ipfs/go-ipfs

COPY . $SRC_DIR

# Build the thing.
# Also: fix getting HEAD commit hash via git rev-parse.
# Also: allow using a custom IPFS API endpoint.
RUN cd $SRC_DIR \
  && mkdir .git/objects \
  && ([ -z "$GX_IPFS" ] || echo $GX_IPFS > /root/.ipfs/api) \
  && make build IPFS_GX_USE_GLOBAL=1 GOFLAGS='-ldflags "-linkmode external -extldflags \"-static\" -s -w"'

# Now comes the actual target image, which aims to be as small as possible.
FROM alpine
MAINTAINER Lars Gierth <lgierth@ipfs.io>

# Get the ipfs binary, entrypoint script, and TLS CAs from the build container.
ENV SRC_DIR /go/src/github.com/ipfs/go-ipfs
COPY --from=0 $SRC_DIR/cmd/ipfs/ipfs /usr/local/bin/ipfs
COPY --from=0 $SRC_DIR/bin/container_daemon /usr/local/bin/start_ipfs
RUN apk -U add su-exec tini

# Ports for Swarm TCP, Swarm uTP, API, Gateway, Swarm Websockets
EXPOSE 4001
EXPOSE 4002/udp
EXPOSE 5001
EXPOSE 8080
EXPOSE 8081

# Create the fs-repo directory and switch to a non-privileged user.
ENV IPFS_PATH /data/ipfs
RUN mkdir -p $IPFS_PATH \
  && adduser -D -h $IPFS_PATH -u 1000 -G users ipfs \
  && chown ipfs:users $IPFS_PATH

# Expose the fs-repo as a volume.
# start_ipfs initializes an fs-repo if none is mounted.
# Important this happens after the USER directive so permission are correct.
VOLUME $IPFS_PATH

# The default logging level
ENV IPFS_LOGGING ""

# This just makes sure that:
# 1. There's an fs-repo, and initializes one if there isn't.
# 2. The API and Gateway are accessible from outside the container.
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/start_ipfs"]

# Execute the daemon subcommand by default
CMD ["daemon", "--migrate=true"]
