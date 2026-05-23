ARG BUILDPLATFORM
ARG TARGETPLATFORM

ARG XBPS_MIRROR=https://repo-fastly.voidlinux.org

ARG CORE_PACKAGES="xbps base-files busybox ca-certificates"
ARG SEARXNG_BUILDER_PACKAGES="xbps base-files busybox ca-certificates gcc tzdata python3-devel wget uv brotli make bash git graphviz"
ARG SEARXNG_PACKAGES="xbps base-files busybox ca-certificates libstdc++ tzdata python3 wget"

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

RUN --mount=type=cache,sharing=locked,id=xbps,target=/target/var/cache/xbps set -eux; \
    . /setup.sh; \
    apk add --no-cache ca-certificates curl; \
    curl "$XBPS_MIRROR/static/xbps-static-latest.$(uname -m)-musl.tar.xz" | tar -C / -vJx; \
    xbps-install -S -R "$REPO" -r /target/

#######
## CORE
#######
FROM --platform=$BUILDPLATFORM bootstrap AS rootfs-core

ARG TARGETPLATFORM
ARG XBPS_MIRROR
ARG CORE_PACKAGES

RUN --mount=type=cache,sharing=locked,id=xbps,target=/target/var/cache/xbps set -eux; \
    . /setup.sh; \
    xbps-install -y -R "$REPO" -r /target/ $CORE_PACKAGES

FROM --platform=$TARGETPLATFORM scratch AS core

COPY --from=rootfs-core /target/ /

RUN set -eu; \
    for app in $(/usr/bin/busybox --list); do \
    [ ! -f "/usr/bin/$app" ] && /usr/bin/busybox ln -sf busybox "/usr/bin/$app"; \
    done; \
    install -dm1777 /tmp/; \
    xbps-reconfigure -fa; \
    rm -rf /var/cache/* /var/db/xbps/https___*

COPY <<EOF /etc/group
root:x:0:
EOF

COPY <<EOF /etc/passwd
root:x:0:0:root:/root/:/usr/bin/sh
EOF

ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    SSL_CERT_DIR="/etc/ssl/certs" \
    SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt" \
    HISTFILE="/dev/null"

WORKDIR /
ENTRYPOINT ["/usr/bin/sh"]

##################
## SEARXNG-BUILDER
##################
FROM --platform=$BUILDPLATFORM rootfs-core AS rootfs-searxng-builder

ARG TARGETPLATFORM
ARG XBPS_MIRROR
ARG SEARXNG_BUILDER_PACKAGES

RUN --mount=type=cache,sharing=locked,id=xbps,target=/target/var/cache/xbps set -eux; \
    . /setup.sh; \
    xbps-install -y -R "$REPO" -r /target/ $SEARXNG_BUILDER_PACKAGES

FROM --platform=$TARGETPLATFORM scratch AS searxng-builder

COPY --from=rootfs-searxng-builder /target/ /

RUN set -eu; \
    for app in $(/usr/bin/busybox --list); do \
    [ ! -f "/usr/bin/$app" ] && /usr/bin/busybox ln -sf busybox "/usr/bin/$app"; \
    done; \
    install -dm1777 /tmp/; \
    xbps-reconfigure -fa; \
    rm -rf /var/cache/* /var/db/xbps/https___*; \
    python -m compileall -q -j 0 /usr/lib/python*/

ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    SSL_CERT_DIR="/etc/ssl/certs" \
    SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt" \
    HISTFILE="/dev/null"

WORKDIR /usr/local/searxng/
ENTRYPOINT ["/usr/bin/sh"]

##########
## SEARXNG
##########
FROM --platform=$BUILDPLATFORM rootfs-core AS rootfs-searxng

ARG TARGETPLATFORM
ARG XBPS_MIRROR
ARG SEARXNG_PACKAGES

RUN --mount=type=cache,sharing=locked,id=xbps,target=/target/var/cache/xbps set -eux; \
    . /setup.sh; \
    xbps-install -y -R "$REPO" -r /target/ $SEARXNG_PACKAGES

FROM --platform=$TARGETPLATFORM scratch AS searxng

COPY --from=rootfs-searxng /target/ /

RUN set -eu; \
    for app in $(/usr/bin/busybox --list); do \
    [ ! -f "/usr/bin/$app" ] && /usr/bin/busybox ln -sf busybox "/usr/bin/$app"; \
    done; \
    install -dm1777 /tmp/; \
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

RUN set -eux; \
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
