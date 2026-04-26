FROM alpine:latest AS build

ARG TINI_VER="v0.19.0"
ARG SUPERVISORD_VER="0.1.0"
ARG TARGETARCH

RUN apk add --no-cache --update wget tar busybox-static && \
    mkdir -p /build/bin/busybox && \
    ## supervisord (pre-built from zzci/supervisord)
    SUP_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "arm64" || echo "x86_64") && \
    wget -qO- "https://github.com/zzci/supervisord/releases/download/v${SUPERVISORD_VER}/supervisord_${SUPERVISORD_VER}_Linux_${SUP_ARCH}.tar.gz" \
        | tar -xz -C /tmp supervisord && \
    mv /tmp/supervisord /build/bin/supervisord && \
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
