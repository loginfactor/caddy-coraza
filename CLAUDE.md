# Caddy + Coraza WAF + OWASP CRS

## Goal

Docker image for Caddy as a **reverse proxy with Web Application Firewall (WAF)**.
Caddy is built with the Coraza WAF plugin and the `caddy-ratelimit` plugin. OWASP Core Rule Set (CRS) is downloaded separately and loaded from the filesystem, so users can mount their own `crs-setup.conf` or exclusion files.
Images are automatically built for new upstream versions and pushed to GitHub Container Registry (ghcr.io).

## Architecture decisions

### Version management (`versions.json`)

Single source of truth for all versions. Read by Dockerfile and GitHub Actions.

- **Caddy + Coraza**: Automatically updated via `scripts/check-versions.sh` (daily cron)
- **CRS**: `crs_versions` is a map (`"minor": "patch"`), e.g. `{"4.25": "4.25.0"}`
  - **Keys** (minor/LTS branches) are managed manually
  - **Values** (patch versions) are updated automatically
  - Each key produces a separate image (matrix build)
- **caddy-ratelimit**: hybrid pinning. Upstream has only one release tag (`v0.1.0`, Aug 2024) that predates fixes we depend on, so the field holds a manually chosen master commit SHA (12 chars). The cron only auto-updates this entry once a release strictly newer than `v0.1.0` ships; from then on it tracks releases like every other module. SHA bumps for security fixes between releases require a manual edit. The Dockerfile passes the value to xcaddy without a `v` prefix so the same field can hold either form.

CRS releases much more frequently than Caddy/Coraza. New CRS branches should be added deliberately, while patch updates within a branch are safe to automate.

### CRS: filesystem-based

CRS rules are downloaded from the official `coreruleset/coreruleset` repo and installed to `/etc/caddy/crs/` in the image. This allows users to mount custom configuration:

- `/etc/caddy/crs/crs-setup.conf` -- override with custom paranoia level, anomaly thresholds, etc.
- Additional exclusion files can be included via the Caddyfile `directives` block

### Docker image

- **Builder**: `golang:<version>-alpine` with xcaddy
- **Runtime**: `registry.access.redhat.com/ubi9/ubi-minimal` (supported until 2032)
- **Purpose**: Reverse proxy with WAF only, no static file serving

### Container hardening

The image is hardened at build time:

- Non-root user `caddy` (1000:1000), no login shell
- Caddy binary read-only (555)
- No Caddyfile or coraza.conf in image (user must mount their own)
- No `EXPOSE` -- ports depend on the user's Caddyfile
- No capabilities -- listen on ports >= 1024, use Docker port mapping for 80/443
- Built-in `HEALTHCHECK`

For full hardening, apply these runtime flags:

```bash
docker run --read-only --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --tmpfs /tmp/caddy caddy-coraza:test
```

- `--read-only`: prevents writes to the container filesystem
- `--cap-drop ALL`: drops all capabilities (no privileged ports needed)
- `--security-opt no-new-privileges:true`: prevents privilege escalation via setuid/setgid binaries
- `--tmpfs /tmp/caddy`: writable tmpfs for runtime temp files

### Image tags (hierarchical)

| Tag | Example | Description |
|---|---|---|
| Exact (immutable) | `2.11.2-2.3.0-4.25.0-b8d8c9a` | Caddy / Coraza / CRS / ratelimit. Pinned, never changes. Ratelimit slot is a 7-char SHA when commit-pinned, full release tag otherwise. |
| CRS minor pinned | `2-2-4.25` | Rolling for Caddy/Coraza, CRS patch |
| CRS major pinned | `2-2-4` | Rolling for everything except major bumps |
| `latest` | `latest` | Most recent build |

### CI/CD

- **`build.yml`**: Builds on push to `main`, tests (health check + WAF test), pushes to GHCR
- **`check-updates.yml`**: Daily cron (06:00 UTC), checks for new versions, commits and pushes automatically, which triggers the build

## File structure

```
versions.json                         # Central version constants
Dockerfile                            # Multi-stage build (xcaddy, UBI9)
test/Caddyfile                        # Test config (respond "OK" 200)
.github/workflows/build.yml           # Build, test & push
.github/workflows/check-updates.yml   # Automatic version check
scripts/check-versions.sh             # Upstream version detection
```

## Style

- Write in a minimalist, natural style
- No emojis, no em dashes, no AI-typical phrasing
- All text output in English
- Commit messages are one-liners (no body, no multi-line)
- No `Co-Authored-By: Claude` or similar attributions

## Local build

```bash
docker build \
  --build-arg GO_VERSION=1.25 \
  --build-arg XCADDY_VERSION=0.4.5 \
  --build-arg CADDY_VERSION=2.11.2 \
  --build-arg CORAZA_CADDY_VERSION=2.3.0 \
  --build-arg CADDY_RATELIMIT_VERSION=b8d8c9a9d99e \
  --build-arg CRS_VERSION=4.25.0 \
  -t caddy-coraza:test .
```

## Testing

```bash
# Start container with test Caddyfile
docker run --rm -d --name caddy-test -p 8080:8080 \
  -v $(pwd)/test/Caddyfile:/etc/caddy/Caddyfile:ro caddy-coraza:test

# Health check (expect 200)
curl -s -o /dev/null -w '%{http_code}' http://localhost:8080

# WAF test: XSS (expect 403)
curl -s -o /dev/null -w '%{http_code}' 'http://localhost:8080?q=<script>alert(1)</script>'

docker stop caddy-test
```
