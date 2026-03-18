FROM golang:alpine AS build

ARG TINI_VER="v0.19.0"
ARG SUPERVISORD_COMMIT="16cb640"
ARG TARGETARCH

RUN apk add --no-cache --update git musl-dev gcc build-base busybox-static && \
    ## mkdir
    mkdir -p /build/bin/busybox && \
    ## supervisord (pinned to latest commit, includes CVE-2024-24786 fix and dependency upgrades)
    git clone https://github.com/ochinchina/supervisord.git /go/src/supervisord && \
    cd /go/src/supervisord && git checkout ${SUPERVISORD_COMMIT} && \
    go build -a -ldflags "-linkmode external -extldflags -static" -o /build/bin/supervisord && \
    ## tini
    TINI_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "arm64" || echo "amd64") && \
    wget -qO /build/bin/tini "https://github.com/krallin/tini/releases/download/${TINI_VER}/tini-static-${TINI_ARCH}" && \
    ## busybox (from alpine package, supports all archs)
    cp /bin/busybox.static /build/bin/busybox/busybox && \
    chmod +x /build/bin/* /build/bin/busybox/busybox

FROM scratch

ENV PATH=$PATH:/build/bin/busybox:/build/bin

COPY --from=build /build/bin/  /build/bin/

ADD rootfs /

CMD ["/start.sh"]
