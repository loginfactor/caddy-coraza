#!/usr/bin/env bash
set -euo pipefail

# Check for new upstream versions of Caddy, Coraza-Caddy, xcaddy, and CRS patches.
# Updates versions.json if newer versions are found.
#
# Usage: check-versions.sh [versions-file] [min-age-days]
#   min-age-days: Only accept releases older than this many days (default: 7, 0 to disable)

VERSIONS_FILE="${1:-versions.json}"
MIN_AGE_DAYS="${2:-7}"
UPDATED=false

# Use GITHUB_TOKEN if available (5000 req/hr vs 60 unauthenticated)
AUTH_HEADER=""
if [ -n "${GITHUB_TOKEN:-}" ]; then
  AUTH_HEADER="Authorization: Bearer ${GITHUB_TOKEN}"
fi

# Calculate cutoff date for minimum release age
CUTOFF_DATE=""
if [ "$MIN_AGE_DAYS" -gt 0 ]; then
  CUTOFF_DATE=$(date -u -d "${MIN_AGE_DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ)
fi

github_api() {
  local url="$1"
  if [ -n "$AUTH_HEADER" ]; then
    curl -sf -H "$AUTH_HEADER" "$url"
  else
    curl -sf "$url"
  fi
}

github_latest_release() {
  local repo="$1"
  local url="https://api.github.com/repos/${repo}/releases"
  local jq_filter

  if [ -n "$CUTOFF_DATE" ]; then
    jq_filter='[.[] | select(.prerelease == false and .draft == false and .published_at <= $cutoff)] | sort_by(.published_at) | last | .tag_name'
  else
    jq_filter='[.[] | select(.prerelease == false and .draft == false)] | sort_by(.published_at) | last | .tag_name'
  fi

  local tag
  tag=$(github_api "$url" | jq -r --arg cutoff "${CUTOFF_DATE:-}" "$jq_filter")

  if [ "$tag" = "null" ] || [ -z "$tag" ]; then
    return 1
  fi

  echo "${tag#v}"
}

github_latest_patch() {
  local repo="$1"
  local minor="$2"
  local url="https://api.github.com/repos/${repo}/releases"
  local jq_filter

  if [ -n "$CUTOFF_DATE" ]; then
    jq_filter='[.[] | select(.tag_name | startswith($minor)) | select(.prerelease == false) | select(.published_at <= $cutoff)] | sort_by(.published_at) | last | .tag_name'
  else
    jq_filter='[.[] | select(.tag_name | startswith($minor)) | select(.prerelease == false)] | sort_by(.published_at) | last | .tag_name'
  fi

  local tag
  tag=$(github_api "$url" | jq -r --arg minor "v${minor}" --arg cutoff "${CUTOFF_DATE:-}" "$jq_filter")

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

  if [ "$current" = "$latest" ]; then
    echo "OK: ${label} ${current} (up to date)"
    return
  fi

  # Never downgrade: only update if latest is actually newer
  local newer
  newer=$(printf '%s\n%s' "$current" "$latest" | sort -V | tail -1)
  if [ "$newer" != "$latest" ]; then
    echo "OK: ${label} ${current} (newer than age-filtered ${latest}, keeping)"
    return
  fi

  echo "UPDATE: ${label} ${current} → ${latest}"
  jq --arg key "$key" --arg val "$latest" '.[$key] = $val' "$VERSIONS_FILE" > tmp.json && mv tmp.json "$VERSIONS_FILE"
  UPDATED=true
}

echo "=== Checking upstream versions ==="
if [ -n "$CUTOFF_DATE" ]; then
  echo "Minimum release age: ${MIN_AGE_DAYS} days (before ${CUTOFF_DATE})"
fi
echo ""

# Check Caddy
CURRENT_CADDY=$(jq -r .caddy "$VERSIONS_FILE")
if LATEST_CADDY=$(github_latest_release "caddyserver/caddy"); then
  update_version "caddy" "$CURRENT_CADDY" "$LATEST_CADDY" "Caddy"
else
  echo "SKIP: Caddy (no release older than ${MIN_AGE_DAYS} days)"
fi

# Check Coraza-Caddy
CURRENT_CORAZA=$(jq -r .coraza_caddy "$VERSIONS_FILE")
if LATEST_CORAZA=$(github_latest_release "corazawaf/coraza-caddy"); then
  update_version "coraza_caddy" "$CURRENT_CORAZA" "$LATEST_CORAZA" "Coraza-Caddy"
else
  echo "SKIP: Coraza-Caddy (no release older than ${MIN_AGE_DAYS} days)"
fi

# Check caddy-ratelimit (hybrid: SHA-pinned until a release > v0.1.0 appears)
# v0.1.0 is the only existing release and predates fixes we depend on, so the
# pin is a manually chosen master commit. The script auto-switches back to
# release tracking the moment a newer release ships upstream.
CURRENT_RATELIMIT=$(jq -r .caddy_ratelimit "$VERSIONS_FILE")
RATELIMIT_FLOOR="0.1.0"
if [[ "$CURRENT_RATELIMIT" == *.* ]]; then
  # Already tag-pinned: standard release tracking
  if LATEST_RATELIMIT=$(github_latest_release "mholt/caddy-ratelimit"); then
    update_version "caddy_ratelimit" "$CURRENT_RATELIMIT" "$LATEST_RATELIMIT" "caddy-ratelimit"
  else
    echo "SKIP: caddy-ratelimit (no release older than ${MIN_AGE_DAYS} days)"
  fi
else
  # SHA-pinned: only switch if a release strictly newer than the floor exists
  if LATEST_RATELIMIT=$(github_latest_release "mholt/caddy-ratelimit"); then
    NEWER=$(printf '%s\n%s' "$RATELIMIT_FLOOR" "$LATEST_RATELIMIT" | sort -V | tail -1)
    if [ "$NEWER" = "$LATEST_RATELIMIT" ] && [ "$LATEST_RATELIMIT" != "$RATELIMIT_FLOOR" ]; then
      echo "UPDATE: caddy-ratelimit ${CURRENT_RATELIMIT} (commit) → ${LATEST_RATELIMIT} (release)"
      jq --arg v "$LATEST_RATELIMIT" '.caddy_ratelimit = $v' "$VERSIONS_FILE" > tmp.json && mv tmp.json "$VERSIONS_FILE"
      UPDATED=true
    else
      echo "OK: caddy-ratelimit ${CURRENT_RATELIMIT} (commit-pinned, no release > v${RATELIMIT_FLOOR})"
    fi
  else
    echo "OK: caddy-ratelimit ${CURRENT_RATELIMIT} (commit-pinned, no qualifying release)"
  fi
fi

# Check xcaddy
CURRENT_XCADDY=$(jq -r .xcaddy "$VERSIONS_FILE")
if LATEST_XCADDY=$(github_latest_release "caddyserver/xcaddy"); then
  update_version "xcaddy" "$CURRENT_XCADDY" "$LATEST_XCADDY" "xcaddy"
else
  echo "SKIP: xcaddy (no release older than ${MIN_AGE_DAYS} days)"
fi

# Check CRS patch versions for each configured minor branch
echo ""
echo "=== Checking CRS patch versions ==="
for MINOR in $(jq -r '.crs_versions | keys[]' "$VERSIONS_FILE"); do
  CURRENT_PATCH=$(jq -r --arg m "$MINOR" '.crs_versions[$m]' "$VERSIONS_FILE")

  if LATEST_PATCH=$(github_latest_patch "coreruleset/coreruleset" "$MINOR"); then
    if [ "$CURRENT_PATCH" = "$LATEST_PATCH" ]; then
      echo "OK: CRS ${MINOR} ${CURRENT_PATCH} (up to date)"
    else
      NEWER=$(printf '%s\n%s' "$CURRENT_PATCH" "$LATEST_PATCH" | sort -V | tail -1)
      if [ "$NEWER" != "$LATEST_PATCH" ]; then
        echo "OK: CRS ${MINOR} ${CURRENT_PATCH} (newer than age-filtered ${LATEST_PATCH}, keeping)"
      else
        echo "UPDATE: CRS ${MINOR} ${CURRENT_PATCH} → ${LATEST_PATCH}"
        jq --arg m "$MINOR" --arg v "$LATEST_PATCH" '.crs_versions[$m] = $v' "$VERSIONS_FILE" > tmp.json && mv tmp.json "$VERSIONS_FILE"
        UPDATED=true
      fi
    fi
  else
    echo "SKIP: CRS ${MINOR} (no release older than ${MIN_AGE_DAYS} days)"
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
