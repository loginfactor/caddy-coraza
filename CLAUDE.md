# Caddy + Coraza WAF + OWASP CRS

## Projektziel

Docker-Image für Caddy als **Reverse Proxy mit Web Application Firewall (WAF)**.
Caddy wird mit dem Coraza WAF Plugin und eingebettetem OWASP Core Rule Set (CRS) gebaut.
Images werden automatisch für neue Upstream-Versionen gebaut und auf GitHub Container Registry (ghcr.io) gepusht.

## Architekturentscheidungen

### Versionsverwaltung (`versions.json`)

Zentrale Datei für alle Versionen. Wird von Dockerfile und GitHub Actions gelesen.

- **Caddy + Coraza**: Werden automatisch via `scripts/check-versions.sh` aktualisiert (täglich per Cron)
- **CRS**: `crs_versions` ist eine Map (`"minor": "patch"`), z.B. `{"4.24": "4.24.1"}`
  - **Keys** (Minor/LTS-Branches) werden manuell gepflegt
  - **Values** (Patch-Versionen) werden automatisch aktualisiert
  - Pro Key wird ein separates Image gebaut (Matrix-Build)

Hintergrund: CRS wird deutlich häufiger released als Caddy/Coraza. Neue CRS-Branches sollen bewusst hinzugefügt werden, Patch-Updates innerhalb eines Branches sind aber automatisch sicher.

### CRS-Versionen: Go-Modul vs. OWASP CRS

Die CRS-Versionen in `versions.json` beziehen sich auf das **Go-Modul** `github.com/corazawaf/coraza-coreruleset`, NICHT auf die offiziellen OWASP CRS Releases. Das Go-Modul hinkt dem offiziellen Release oft hinterher. Vor Versionsänderungen immer prüfen ob die Version als Go-Modul existiert:

```bash
curl -sf "https://api.github.com/repos/corazawaf/coraza-coreruleset/releases" | jq -r '.[].tag_name'
```

### Docker Image

- **Builder**: `golang:<version>-alpine` mit xcaddy
- **Runtime**: `registry.access.redhat.com/ubi9/ubi-minimal` (Support bis 2032)
- **Einsatzzweck**: Nur Reverse Proxy mit WAF — keine statischen Dateien

### Image-Tags (hierarchisch)

| Tag | Beispiel | Beschreibung |
|---|---|---|
| Exakt (immutable) | `2.11.2-2.3.0-4.24.1` | Pinned, ändert sich nie |
| CRS-Minor pinned | `2-2-4.24` | Rolling für Caddy/Coraza, CRS-Patch |
| CRS-Major pinned | `2-2-4` | Rolling für alles außer Major-Bumps |
| `latest` | `latest` | Neuester Build |

### CI/CD

- **`build.yml`**: Baut bei Push auf `main`, testet (Health-Check + WAF-Test), pusht zu GHCR
- **`check-updates.yml`**: Täglicher Cron (06:00 UTC), prüft neue Versionen, committed und pusht automatisch → triggert Build

## Dateistruktur

```
versions.json                         # Zentrale Versionskonstanten
Dockerfile                            # Multi-Stage Build (xcaddy → UBI9)
Caddyfile                             # Default-Konfiguration (reverse_proxy + WAF)
test/Caddyfile                        # Test-Konfiguration (respond "OK" 200)
.github/workflows/build.yml           # Build, Test & Push
.github/workflows/check-updates.yml   # Automatischer Version-Check
scripts/check-versions.sh             # Upstream-Version-Erkennung
```

## Git-Konventionen

- Commit-Messages sind **Einzeiler** (kein Body, kein Multi-Line)
- **Kein** `Co-Authored-By: Claude` oder ähnliche Zuschreibungen

## Lokaler Build

```bash
docker build \
  --build-arg GO_VERSION=1.25 \
  --build-arg CADDY_VERSION=2.11.2 \
  --build-arg CORAZA_CADDY_VERSION=2.3.0 \
  --build-arg CRS_VERSION=4.24.1 \
  -t caddy-coraza:test .
```

## Testen

```bash
# Container mit Test-Caddyfile starten
docker run --rm -d --name caddy-test -p 8080:80 \
  -v $(pwd)/test/Caddyfile:/etc/caddy/Caddyfile:ro caddy-coraza:test

# Health-Check (erwartet 200)
curl -s -o /dev/null -w '%{http_code}' http://localhost:8080

# WAF-Test: XSS (erwartet 403)
curl -s -o /dev/null -w '%{http_code}' 'http://localhost:8080?q=<script>alert(1)</script>'

docker stop caddy-test
```
