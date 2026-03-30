ARG GO_VERSION=1.25

# Stage 1: Build Caddy with Coraza WAF plugin
FROM golang:${GO_VERSION}-alpine AS builder

ARG CADDY_VERSION
ARG CORAZA_CADDY_VERSION
ARG CRS_VERSION

RUN apk add --no-cache git && \
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

RUN xcaddy build v${CADDY_VERSION} \
    --with github.com/corazawaf/coraza-caddy/v2@v${CORAZA_CADDY_VERSION} \
    --with github.com/corazawaf/coraza-coreruleset/v4@v${CRS_VERSION}

# Stage 2: Runtime
FROM registry.access.redhat.com/ubi9/ubi-minimal

RUN microdnf install -y ca-certificates libcap mailcap && \
    microdnf clean all

COPY --from=builder /go/caddy /usr/bin/caddy

RUN mkdir -p /config/caddy /data/caddy /etc/caddy /usr/share/caddy && \
    setcap cap_net_bind_service=+ep /usr/bin/caddy

COPY Caddyfile /etc/caddy/Caddyfile

ENV XDG_CONFIG_HOME=/config
ENV XDG_DATA_HOME=/data

EXPOSE 80 443 443/udp 2019

CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
