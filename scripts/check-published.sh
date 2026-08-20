#!/usr/bin/env bash
set -euo pipefail

USAGE="\
check-published.sh — exit 0 iff <name>-v<version> (from the module's
metadata.json) is a GitHub release carrying BOTH a .lgx and a
sidecar.json asset. A half-published release (missing either asset)
exits 1 so the module rebuilds and self-heals on the next run.

Usage:
  check-published.sh <module-dir-name>

Environment:
  GH_REPO   (required)  e.g. logos-co/logos-modules-release
  GH_TOKEN  (optional)  avoids anon API rate limits (60 req/h per IP)
                        and allows private catalogs

Exit codes (the caller dispatches on these):
  0  fully published — skip the build
  1  not or half published — build / heal
  2  could not determine (usage, network, API error) — caller should
     abort loudly instead of silently rebuilding everything"

usage() { printf '%s\n' "$USAGE"; }
log()   { printf '%s\n' "$*"; }
die()   { printf 'ERROR: %s\n' "$*" >&2; exit 2; }

cleanup() { [[ -n "${resp:-}" ]] && rm -f "$resp"; }
trap cleanup EXIT

read_tag() {
  local meta="submodules/${module}/metadata.json" name ver
  [[ -f "$meta" ]] || die "no metadata.json for ${module}"
  name=$(jq -r '.name' "$meta")
  ver=$(jq -r '.version' "$meta")
  [[ -n "$name" && "$name" != "null" ]] || die 'metadata.json missing name'
  [[ -n "$ver"  && "$ver"  != "null" ]] || die 'metadata.json missing version'
  tag="${name}-v${ver}"
}

fetch_release() {
  local url="https://api.github.com/repos/${GH_REPO}/releases/tags/${tag}"
  local auth=() http_code
  [[ -n "${GH_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${GH_TOKEN}")
  resp=$(mktemp)
  http_code=$(curl -sS --retry 3 -o "$resp" -w '%{http_code}' \
    "${auth[@]}" \
    -H 'Accept: application/vnd.github+json' \
    "$url") || die "API request to ${url} failed (network error)"
  case "$http_code" in
    200) ;;
    404) log "${tag}: no release"; exit 1 ;;
    *)   cat "$resp" >&2 || true
         die "${tag}: API check failed (HTTP ${http_code})" ;;
  esac
}

main() {
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
  esac
  [[ $# -eq 1 ]] || { usage >&2; exit 2; }
  : "${GH_REPO:?GH_REPO must be set (e.g. logos-co/logos-modules-release)}"
  module="$1"

  read_tag
  fetch_release

  local has_lgx has_side
  has_lgx=$(jq '[.assets[]?.name | select(endswith(".lgx"))] | length' "$resp") \
    || die "${tag}: could not parse API response"
  has_side=$(jq '[.assets[]?.name | select(. == "sidecar.json")] | length' "$resp") \
    || die "${tag}: could not parse API response"

  if [[ "$has_lgx" -gt 0 && "$has_side" -gt 0 ]]; then
    log "${tag}: fully published"
    exit 0
  fi
  log "${tag}: release exists but missing assets (lgx=${has_lgx}, sidecar=${has_side}) — will heal"
  exit 1
}

main "$@"