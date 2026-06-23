ARG BUILDPLATFORM
ARG TARGETPLATFORM

ARG XBPS_MIRROR=https://repo-fastly.voidlinux.org

ARG SEARXNG_BUILDER_PACKAGES="xbps base-files busybox ca-certificates gcc tzdata brotli wget python3-devel uv"

ARG CORE_PACKAGES="xbps base-files busybox ca-certificates"
ARG SEARXNG_PACKAGES="libstdc++ tzdata python3 wget"

ARG CI_PACKAGES="bash dash sudo gcc ldd-check make wget git gnutar gzip brotli zstd podman fuse-overlayfs nftables mount just-newuidmap-newgidmap nodejs-26 python-3.14-dev py3.14-pip uv graphviz-graphs"

############
## BOOTSTRAP
############
FROM --platform=$BUILDPLATFORM docker.io/library/alpine:latest AS bootstrap

ARG TARGETPLATFORM
ARG XBPS_MIRROR

COPY ./setup.sh /
COPY ./keys/ /target/var/db/xbps/keys/
COPY <<EOF /target/etc/xbps.d/noextract.conf
noextract=/etc/colors*
noextract=/etc/crypttab
noextract=/etc/fstab
noextract=/etc/gai.conf
noextract=/etc/hosts
noextract=/etc/inputrc
noextract=/etc/issue
noextract=/etc/mtab
noextract=/etc/profile*
noextract=/etc/rpc
noextract=/etc/securetty
noextract=/etc/skel*
noextract=/etc/sv*
noextract=/usr/lib/dracut*
noextract=/usr/lib/gconv*
noextract=/usr/lib/modprobe.d*
noextract=/usr/lib/python*/EXTERNALLY-MANAGED
noextract=/usr/lib/sysctl.d*
noextract=/usr/lib/udev*
noextract=/usr/libexec/xbps-triggers/appstream-cache
noextract=/usr/libexec/xbps-triggers/binfmts
noextract=/usr/libexec/xbps-triggers/dkms
noextract=/usr/libexec/xbps-triggers/gconf-schemas
noextract=/usr/libexec/xbps-triggers/gdk-pixbuf-loaders
noextract=/usr/libexec/xbps-triggers/gio-modules
noextract=/usr/libexec/xbps-triggers/gsettings-schemas
noextract=/usr/libexec/xbps-triggers/gtk3-immodules
noextract=/usr/libexec/xbps-triggers/gtk-icon-cache
noextract=/usr/libexec/xbps-triggers/gtk-immodules
noextract=/usr/libexec/xbps-triggers/gtk-pixbuf-loaders
noextract=/usr/libexec/xbps-triggers/hwdb.d-dir
noextract=/usr/libexec/xbps-triggers/info-files
noextract=/usr/libexec/xbps-triggers/initramfs-regenerate
noextract=/usr/libexec/xbps-triggers/kernel-hooks
noextract=/usr/libexec/xbps-triggers/mimedb
noextract=/usr/libexec/xbps-triggers/pango-modules
noextract=/usr/libexec/xbps-triggers/pycompile
noextract=/usr/libexec/xbps-triggers/system-accounts
noextract=/usr/libexec/xbps-triggers/texmf-dist
noextract=/usr/libexec/xbps-triggers/update-desktopdb
noextract=/usr/libexec/xbps-triggers/x11-fonts
noextract=/usr/libexec/xbps-triggers/xml-catalog
noextract=/usr/share/bash-completion*
noextract=/usr/share/fish/vendor_completions.d*
noextract=/usr/share/info*
noextract=/usr/share/licenses*
noextract=/usr/share/man*
noextract=/usr/share/zsh/site-functions*
EOF

COPY <<EOF /target/etc/group
root:x:0:
EOF

COPY <<EOF /target/etc/passwd
root:x:0:0:root:/root/:/usr/bin/sh
EOF

RUN --mount=type=cache,sharing=locked,id=xbps,target=/target/var/cache/xbps set -euxo pipefail; \
    . /setup.sh; \
    apk add --no-cache ca-certificates curl; \
    curl "$XBPS_MIRROR/static/xbps-static-latest.$(uname -m)-musl.tar.xz" | tar -C / -vJx; \
    xbps-install -S -R "$REPO" -r /target/; \
    install -dm1777 /target/tmp/; \
    install -dm1777 /target/var/tmp/; \
    install -dm0750 /target/root/

##################
## SEARXNG-BUILDER
##################
FROM --platform=$BUILDPLATFORM bootstrap AS rootfs-searxng-builder

ARG TARGETPLATFORM
ARG XBPS_MIRROR
ARG SEARXNG_BUILDER_PACKAGES

RUN --mount=type=cache,sharing=locked,id=xbps,target=/target/var/cache/xbps set -euxo pipefail; \
    . /setup.sh; \
    xbps-install -y -R "$REPO" -r /target/ $SEARXNG_BUILDER_PACKAGES

FROM --platform=$TARGETPLATFORM scratch AS searxng-builder

COPY --from=rootfs-searxng-builder /target/ /

RUN set -eu; \
    for app in $(/usr/bin/busybox --list); do \
    [ ! -f "/usr/bin/$app" ] && /usr/bin/busybox ln -s busybox "/usr/bin/$app"; \
    done; \
    xbps-reconfigure -fa; \
    rm -rf /var/cache/* /var/db/xbps/https___*; \
    python -m compileall -q -j 0 /usr/lib/python*/

ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    SSL_CERT_DIR="/etc/ssl/certs" \
    SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt" \
    HISTFILE="/dev/null"

WORKDIR /usr/local/searxng/
ENTRYPOINT ["/usr/bin/sh"]

#######
## CORE
#######
FROM --platform=$BUILDPLATFORM bootstrap AS rootfs-core

ARG TARGETPLATFORM
ARG XBPS_MIRROR
ARG CORE_PACKAGES

RUN --mount=type=cache,sharing=locked,id=xbps,target=/target/var/cache/xbps set -euxo pipefail; \
    . /setup.sh; \
    xbps-install -y -R "$REPO" -r /target/ $CORE_PACKAGES

FROM --platform=$TARGETPLATFORM scratch AS core

COPY --from=rootfs-core /target/ /

RUN set -eu; \
    for app in $(/usr/bin/busybox --list); do \
    [ ! -f "/usr/bin/$app" ] && /usr/bin/busybox ln -s busybox "/usr/bin/$app"; \
    done; \
    xbps-reconfigure -fa; \
    rm -rf /var/cache/* /var/db/xbps/https___*

ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    SSL_CERT_DIR="/etc/ssl/certs" \
    SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt" \
    HISTFILE="/dev/null"

WORKDIR /root/
ENTRYPOINT ["/usr/bin/sh"]

##########
## SEARXNG
##########
FROM --platform=$BUILDPLATFORM rootfs-core AS rootfs-searxng

ARG TARGETPLATFORM
ARG XBPS_MIRROR
ARG SEARXNG_PACKAGES

RUN --mount=type=cache,sharing=locked,id=xbps,target=/target/var/cache/xbps set -euxo pipefail; \
    . /setup.sh; \
    xbps-install -y -R "$REPO" -r /target/ $SEARXNG_PACKAGES

FROM --platform=$TARGETPLATFORM scratch AS searxng

COPY --from=rootfs-searxng /target/ /

RUN set -eu; \
    for app in $(/usr/bin/busybox --list); do \
    [ ! -f "/usr/bin/$app" ] && /usr/bin/busybox ln -s busybox "/usr/bin/$app"; \
    done; \
    xbps-reconfigure -fa; \
    xbps-remove -Rofy xbps; \
    rm -rf /var/cache/* /var/libexec/xbps* /etc/xbps* /var/db/; \
    python -m compileall -q -j 0 /usr/lib/python*/

COPY <<EOF /etc/group
root:x:0:
searxng:x:977:
EOF

COPY <<EOF /etc/passwd
root:x:0:0:root:/usr/local/searxng/:/usr/bin/sh
searxng:x:977:977:searxng:/usr/local/searxng/:/usr/bin/sh
EOF

RUN set -eu; \
    install -dm0555 -o 977 -g 977 /usr/local/searxng/; \
    install -dm0755 -o 977 -g 977 /etc/searxng/; \
    install -dm0755 -o 977 -g 977 /var/cache/searxng/

ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    SSL_CERT_DIR="/etc/ssl/certs" \
    SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt" \
    HISTFILE="/dev/null" \
    __SEARXNG_CONFIG_PATH="/etc/searxng" \
    __SEARXNG_DATA_PATH="/var/cache/searxng"

WORKDIR /usr/local/searxng/
ENTRYPOINT ["/usr/bin/sh"]

#####
## CI
#####
FROM --platform=$TARGETPLATFORM scratch AS ci
COPY --chown=0:0 --from=cgr.dev/chainguard/wolfi-base:latest / /

COPY <<EOF /etc/passwd
root:x:0:0:root:/root/:/usr/bin/sh
nonroot:x:65532:65532:nonroot:/home/nonroot/:/usr/bin/sh
EOF

COPY <<EOF /etc/group
root:x:0:
nonroot:x:65532:
EOF

COPY <<EOF /etc/subuid
nonroot:100000:65536
EOF

COPY <<EOF /etc/subgid
nonroot:100000:65536
EOF

RUN set -euxo pipefail; \
    install -dm0750 -o 65532 -g 65532 /home/nonroot/; \
    install -dm0750 -o 65532 -g 65532 /home/nonroot/.config/; \
    install -dm0750 -o 65532 -g 65532 /home/nonroot/.config/containers/

COPY --chown=65532:65532 <<EOF /home/nonroot/.config/containers/storage.conf
EOF

ARG CI_PACKAGES

RUN --mount=type=cache,sharing=locked,id=apk,target=/var/cache/apk set -euxo pipefail; \
    apk add --cache-dir /var/cache/apk/ $CI_PACKAGES; \
    ln -s /usr/bin/podman /usr/bin/docker

# FIXME: use dist podman
# https://github.com/podman-container-tools/buildah/issues/6890
ARG TARGETARCH
ARG PODMAN_VERSION=v5.8.4

RUN set -euxo pipefail; \
    apk add --no-cache iptables-nft; \
    ln -sf /usr/sbin/iptables-nft /usr/sbin/iptables; \
    wget -O /tmp/podman.tar.gz "https://github.com/mgoltzsche/podman-static/releases/download/${PODMAN_VERSION}/podman-linux-${TARGETARCH}.tar.gz"; \
    wget -O /tmp/podman.tar.gz.asc "https://github.com/mgoltzsche/podman-static/releases/download/${PODMAN_VERSION}/podman-linux-${TARGETARCH}.tar.gz.asc"; \
    tar -xzf /tmp/podman.tar.gz -C /tmp; \
    cp -rfv /tmp/podman-linux-${TARGETARCH}/usr/. /usr/; \
    rm -rf /tmp/* /root/.wget-hsts

COPY <<EOF /etc/sudoers
root ALL=(ALL) NOPASSWD:ALL
nonroot ALL=(ALL) NOPASSWD:ALL
EOF

ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    SSL_CERT_DIR="/etc/ssl/certs" \
    SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt" \
    HISTFILE="/dev/null"

WORKDIR /
ENTRYPOINT ["/usr/bin/sh"]
