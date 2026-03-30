#!/usr/bin/env bash
set -euo pipefail

# Check for new upstream versions of Caddy, Coraza-Caddy, and CRS patches.
# Updates versions.json if newer versions are found.
# Exit code 0 = updates found, exit code 1 = no updates or error.

VERSIONS_FILE="${1:-versions.json}"
UPDATED=false

# Use GITHUB_TOKEN if available (5000 req/hr vs 60 unauthenticated)
AUTH_HEADER=""
if [ -n "${GITHUB_TOKEN:-}" ]; then
  AUTH_HEADER="Authorization: Bearer ${GITHUB_TOKEN}"
fi

github_latest_release() {
  local repo="$1"
  local url="https://api.github.com/repos/${repo}/releases/latest"
  local tag

  if [ -n "$AUTH_HEADER" ]; then
    tag=$(curl -sf -H "$AUTH_HEADER" "$url" | jq -r '.tag_name')
  else
    tag=$(curl -sf "$url" | jq -r '.tag_name')
  fi

  # Strip leading 'v'
  echo "${tag#v}"
}

github_latest_patch() {
  local repo="$1"
  local minor="$2"
  local url="https://api.github.com/repos/${repo}/releases"

  local tag
  if [ -n "$AUTH_HEADER" ]; then
    tag=$(curl -sf -H "$AUTH_HEADER" "$url" | jq -r --arg minor "v${minor}" '[.[] | select(.tag_name | startswith($minor)) | select(.prerelease == false)] | sort_by(.published_at) | last | .tag_name')
  else
    tag=$(curl -sf "$url" | jq -r --arg minor "v${minor}" '[.[] | select(.tag_name | startswith($minor)) | select(.prerelease == false)] | sort_by(.published_at) | last | .tag_name')
  fi

  if [ "$tag" = "null" ] || [ -z "$tag" ]; then
    return 1
  fi

  echo "${tag#v}"
}

update_version() {
  local key="$1"
  local current="$2"
  local latest="$3"
  local label="$4"

  if [ "$current" != "$latest" ]; then
    echo "UPDATE: ${label} ${current} → ${latest}"
    jq --arg key "$key" --arg val "$latest" '.[$key] = $val' "$VERSIONS_FILE" > tmp.json && mv tmp.json "$VERSIONS_FILE"
    UPDATED=true
  else
    echo "OK: ${label} ${current} (up to date)"
  fi
}

echo "=== Checking upstream versions ==="
echo ""

# Check Caddy
CURRENT_CADDY=$(jq -r .caddy "$VERSIONS_FILE")
LATEST_CADDY=$(github_latest_release "caddyserver/caddy")
update_version "caddy" "$CURRENT_CADDY" "$LATEST_CADDY" "Caddy"

# Check Coraza-Caddy
CURRENT_CORAZA=$(jq -r .coraza_caddy "$VERSIONS_FILE")
LATEST_CORAZA=$(github_latest_release "corazawaf/coraza-caddy")
update_version "coraza_caddy" "$CURRENT_CORAZA" "$LATEST_CORAZA" "Coraza-Caddy"

# Check CRS patch versions for each configured minor branch
echo ""
echo "=== Checking CRS patch versions ==="
for MINOR in $(jq -r '.crs_versions | keys[]' "$VERSIONS_FILE"); do
  CURRENT_PATCH=$(jq -r --arg m "$MINOR" '.crs_versions[$m]' "$VERSIONS_FILE")

  if LATEST_PATCH=$(github_latest_patch "corazawaf/coraza-coreruleset" "$MINOR"); then
    if [ "$CURRENT_PATCH" != "$LATEST_PATCH" ]; then
      echo "UPDATE: CRS ${MINOR} ${CURRENT_PATCH} → ${LATEST_PATCH}"
      jq --arg m "$MINOR" --arg v "$LATEST_PATCH" '.crs_versions[$m] = $v' "$VERSIONS_FILE" > tmp.json && mv tmp.json "$VERSIONS_FILE"
      UPDATED=true
    else
      echo "OK: CRS ${MINOR} ${CURRENT_PATCH} (up to date)"
    fi
  else
    echo "WARN: No release found for CRS ${MINOR}.x"
  fi
done

echo ""
if [ "$UPDATED" = true ]; then
  echo "updated=true"
  exit 0
else
  echo "updated=false"
  exit 1
fi
