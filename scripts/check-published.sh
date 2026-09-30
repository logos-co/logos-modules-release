#!/usr/bin/env bash
set -euo pipefail

USAGE="\
check-published.sh - given module dir names, print the ones that are
NOT fully published, one per line on stdout (all diagnostics go to
stderr). A module counts as published when its <name>-v<version>
GitHub release (version from submodules/<module>/metadata.json)
carries BOTH a .lgx and a sidecar.json asset. Index membership is
not checked here: the index is rebuilt from all published releases
by the rebuild-index workflow (release-triggered + 6-hourly cron),
so any published release lands in the index automatically.

Usage:
  check-published.sh <module-dir-name>...

Environment:
  GH_REPO   (required)  e.g. logos-co/logos-modules-release
  GH_TOKEN  (optional)  avoids anon API rate limits (60 req/h per IP)
                        and allows private catalogs

Exit codes:
  0  determination complete - stdout holds the modules to build
     (possibly empty = everything published)
  2  could not determine (usage, network, API error) - the caller
     must abort instead of rebuilding everything"

usage() { printf '%s\n' "$USAGE"; }
log()   { printf '%s\n' "$*" >&2; }
die()   { printf 'ERROR: %s\n' "$*" >&2; exit 2; }

cleanup() { [[ -n "${resp:-}" ]] && rm -f "$resp"; }
trap cleanup EXIT

# Prints the module's release tag derived from its metadata.json.
module_tag() {
  local module="$1" meta name ver
  meta="submodules/${module}/metadata.json"
  [[ -f "$meta" ]] || die "no metadata.json for ${module}"
  name=$(jq -r '.name' "$meta")
  ver=$(jq -r '.version' "$meta")
  [[ -n "$name" && "$name" != "null" ]] || die "${module}: metadata.json missing name"
  [[ -n "$ver"  && "$ver"  != "null" ]] || die "${module}: metadata.json missing version"
  printf '%s-v%s\n' "$name" "$ver"
}

# Returns 0 if the tag's release exists with both assets, 1 otherwise.
release_complete() {
  local tag="$1" url http_code has_lgx has_side
  url="https://api.github.com/repos/${GH_REPO}/releases/tags/${tag}"
  resp=$(mktemp)
  http_code=$(curl -sS --retry 3 -o "$resp" -w '%{http_code}' \
    "${auth[@]}" \
    -H 'Accept: application/vnd.github+json' \
    "$url") || die "API request to ${url} failed (network error)"
  case "$http_code" in
    200) ;;
    404) log "${tag}: no release"; rm -f "$resp"; return 1 ;;
    *)   cat "$resp" >&2 || true
         die "${tag}: API check failed (HTTP ${http_code})" ;;
  esac
  has_lgx=$(jq '[.assets[]?.name | select(endswith(".lgx"))] | length' "$resp") \
    || die "${tag}: could not parse API response"
  has_side=$(jq '[.assets[]?.name | select(. == "sidecar.json")] | length' "$resp") \
    || die "${tag}: could not parse API response"
  rm -f "$resp"
  if [[ "$has_lgx" -eq 0 || "$has_side" -eq 0 ]]; then
    log "${tag}: release exists but missing assets (lgx=${has_lgx}, sidecar=${has_side}) - will heal"
    return 1
  fi
  return 0
}

main() {
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
  esac
  [[ $# -ge 1 ]] || { usage >&2; exit 2; }
  [[ -n "${GH_REPO:-}" ]] || die 'GH_REPO must be set (e.g. logos-co/logos-modules-release)'

  auth=()
  [[ -n "${GH_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${GH_TOKEN}")

  local module tag
  for module in "$@"; do
    tag=$(module_tag "$module")
    if release_complete "$tag"; then
      log "SKIP ${module} (${tag}): fully published"
    else
      printf '%s\n' "$module"
    fi
  done
}

main "$@"