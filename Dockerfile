ARG GO_VERSION=1.25

# Stage 1: Build Caddy with Coraza WAF plugin (native cross-compilation)
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine AS builder

ARG TARGETARCH
ARG TARGETOS
ARG CADDY_VERSION
ARG CORAZA_CADDY_VERSION
ARG CRS_VERSION
ARG XCADDY_VERSION

RUN apk add --no-cache git && \
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@v${XCADDY_VERSION}

ENV GOOS=${TARGETOS} \
    GOARCH=${TARGETARCH}

RUN xcaddy build v${CADDY_VERSION} \
    --with github.com/corazawaf/coraza-caddy/v2@v${CORAZA_CADDY_VERSION}

# Download and extract OWASP CRS
ADD https://github.com/coreruleset/coreruleset/archive/refs/tags/v${CRS_VERSION}.tar.gz /tmp/crs.tar.gz
RUN tar -xzf /tmp/crs.tar.gz -C /tmp && \
    mkdir -p /tmp/crs && \
    mv /tmp/coreruleset-${CRS_VERSION}/rules /tmp/crs/rules && \
    cp /tmp/coreruleset-${CRS_VERSION}/crs-setup.conf.example /tmp/crs/crs-setup.conf

# Stage 2: Runtime
FROM registry.access.redhat.com/ubi9/ubi-minimal

RUN microdnf update -y && \
    microdnf install -y ca-certificates libcap mailcap && \
    microdnf clean all

RUN groupadd --gid 1000 caddy && \
    useradd --uid 1000 --gid caddy --home-dir /data --no-create-home --shell /sbin/nologin caddy

COPY --from=builder --chmod=555 /go/caddy /usr/bin/caddy
COPY --from=builder /tmp/crs /etc/caddy/crs

RUN mkdir -p /config/caddy /data/caddy /etc/caddy /tmp/caddy && \
    chown -R caddy:caddy /config /data /tmp/caddy && \
    setcap cap_net_bind_service=+ep /usr/bin/caddy

COPY --chmod=444 coraza.conf /etc/caddy/coraza.conf
COPY --chmod=444 Caddyfile /etc/caddy/Caddyfile

ENV XDG_CONFIG_HOME=/config
ENV XDG_DATA_HOME=/data
ENV TMPDIR=/tmp/caddy

EXPOSE 80 443 443/udp

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD ["caddy", "version"]

USER caddy

CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
