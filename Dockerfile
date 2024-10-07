FROM golang:alpine AS build

ARG TINI_VER="v0.19.0"
ARG BUSYBOX_VER="1.35.0-x86_64-linux-musl"

RUN apk add --no-cache --update git musl-dev gcc build-base && \
    ## mkdir
    mkdir -p /build/bin/busybox /go/src/supervisord && \
    ## supervisord
    wget -qO- https://github.com/ochinchina/supervisord/archive/refs/tags/v0.7.3.tar.gz | tar xz --strip 1 -C /go/src/supervisord && \
    cd /go/src/supervisord && go build -a -ldflags "-linkmode external -extldflags -static" -o /build/bin/supervisord && \
    wget -qO /build/bin/tini https://github.com/krallin/tini/releases/download/${TINI_VER}/tini-static && \
    wget -qO /build/bin/busybox/busybox https://busybox.net/downloads/binaries/${BUSYBOX_VER}/busybox && \
    chmod +x /build/bin/* /build/bin/busybox/busybox

FROM scratch

ENV PATH=$PATH:/build/bin/busybox:/build/bin

COPY --from=build /build/bin/  /build/bin/

ADD rootfs /

CMD ["/start.sh"]
