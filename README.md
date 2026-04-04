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

The default Caddyfile sets up Coraza WAF with OWASP CRS in front of a reverse proxy. Mount your own Caddyfile to configure the upstream:

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
}

example.com {
    coraza_waf {
        load_owasp_crs
        directives `
            Include @coraza.conf-recommended
            Include @crs-setup.conf.example
            Include @owasp_crs/*.conf
            SecRuleEngine On
        `
    }
    reverse_proxy backend:8080
}
```

## Versions

All versions are defined in `versions.json`. Caddy and Coraza are updated automatically. CRS minor branches are added manually, patch versions within a branch are updated automatically.

CRS versions refer to the Go module `github.com/corazawaf/coraza-coreruleset`, which may lag behind official OWASP CRS releases.

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
