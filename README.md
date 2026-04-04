# caddy-coraza

Docker image for Caddy with Coraza WAF and OWASP Core Rule Set.

Built for use as a reverse proxy with web application firewall.

## Image tags

Images follow the pattern `CaddyVersion-CorazaVersion-CRSVersion`.

| Tag | Example | Updates |
|---|---|---|
| Exact | `2.11.2-2.3.0-4.25.0` | Never (immutable) |
| CRS minor pinned | `2-2-4.25` | Caddy/Coraza patches, CRS patches |
| CRS major pinned | `2-2-4` | Everything except major bumps |
| `latest` | `latest` | Every build |

```bash
docker pull ghcr.io/<owner>/caddy-coraza:2-2-4.25
```

## Usage

The image ships Caddy with Coraza and CRS rules but no Caddyfile. Mount your own:

```bash
docker run -d -p 80:80 -p 443:443 \
  -v /path/to/Caddyfile:/etc/caddy/Caddyfile:ro \
  -v caddy_data:/data \
  ghcr.io/<owner>/caddy-coraza:latest
```

Example Caddyfile:

```caddyfile
{
    order coraza_waf first
    admin off
}

example.com {
    coraza_waf {
        directives `
            SecRequestBodyAccess On
            SecRequestBodyLimit 13107200
            SecRequestBodyNoFilesLimit 131072
            SecResponseBodyAccess On
            SecResponseBodyMimeType text/plain text/html text/xml
            SecResponseBodyLimit 1048576
            SecResponseBodyLimitAction ProcessPartial
            SecArgumentSeparator &
            SecCookieFormat 0
            SecAuditEngine Off
            SecAuditLog /dev/stderr
            Include /etc/caddy/crs/crs-setup.conf
            Include /etc/caddy/crs/rules/*.conf
            SecRuleEngine On
        `
    }
    reverse_proxy backend:8080
}
```

## Hardening

The image runs as non-root user `caddy` (1000:1000) with read-only binaries and config. The Caddy admin API is disabled.

For full hardening, add these runtime flags:

```bash
docker run --read-only --cap-drop ALL --cap-add NET_BIND_SERVICE \
  --security-opt no-new-privileges:true \
  --tmpfs /tmp/caddy \
  -p 80:80 -p 443:443 \
  -v /path/to/Caddyfile:/etc/caddy/Caddyfile:ro \
  -v caddy_data:/data \
  ghcr.io/<owner>/caddy-coraza:latest
```

| Flag | Effect |
|---|---|
| `--read-only` | Prevents writes to the container filesystem |
| `--cap-drop ALL --cap-add NET_BIND_SERVICE` | Drops all capabilities except binding to ports < 1024 |
| `--security-opt no-new-privileges:true` | Prevents privilege escalation |
| `--tmpfs /tmp/caddy` | Writable tmpfs for runtime temp files |

## Versions

All versions are defined in `versions.json`. Caddy and Coraza are updated automatically. CRS minor branches are added manually, patch versions within a branch are updated automatically.

CRS rules are installed to `/etc/caddy/crs/`. Mount a custom `crs-setup.conf` to adjust paranoia level, anomaly thresholds, or add exclusion rules.

## Building locally

```bash
docker build \
  --build-arg GO_VERSION=1.25 \
  --build-arg CADDY_VERSION=2.11.2 \
  --build-arg CORAZA_CADDY_VERSION=2.3.0 \
  --build-arg CRS_VERSION=4.25.0 \
  -t caddy-coraza:test .
```

## Components

- [Caddy](https://caddyserver.com/) - Web server with automatic HTTPS
- [Coraza](https://coraza.io/) - OWASP ModSecurity compatible WAF engine
- [OWASP CRS](https://coreruleset.org/) - Core Rule Set for WAF protection
