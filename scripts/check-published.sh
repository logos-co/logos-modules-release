#!/usr/bin/env bash
set -euo pipefail

USAGE="\
check-published.sh - print the given modules that are NOT fully published,
one per line on stdout (diagnostics go to stderr). A module is published
when its <name>-v<version> GitHub release has both a .lgx and sidecar.json.

Usage:
  check-published.sh <module-dir-name>...

Environment:
  GH_REPO   (required)  e.g. logos-co/logos-modules-release
  GH_TOKEN  (optional)  avoids anonymous API rate limits

Exit codes:
  0  stdout holds the modules to build (empty = all published)
  2  could not determine - the caller must abort"

log() { printf '%s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }

module_tag() {
  local meta="submodules/$1/metadata.json" name ver
  [[ -f "$meta" ]] || die "no ${meta}"
  name=$(jq -er .name "$meta")   || die "${meta}: missing name"
  ver=$(jq -er .version "$meta") || die "${meta}: missing version"
  echo "${name}-v${ver}"
}

release_complete() {
  local tag="$1" url resp code complete
  url="https://api.github.com/repos/${GH_REPO}/releases/tags/${tag}"
  resp=$(curl -sS --retry 3 -w '\n%{http_code}' "${auth[@]}" \
           -H 'Accept: application/vnd.github+json' "$url") \
    || die "${tag}: request to ${url} failed"
  code=${resp##*$'\n'}
  resp=${resp%$'\n'*}

  case "$code" in
    200) ;;
    404) log "${tag}: no release"; return 1 ;;
    *)   log "$resp"; die "${tag}: GitHub API returned HTTP ${code}" ;;
  esac

  complete=$(jq '[.assets[]?.name] | any(endswith(".lgx")) and any(. == "sidecar.json")' <<<"$resp") \
    || die "${tag}: could not parse API response"
  if [[ "$complete" != true ]]; then
    log "${tag}: release is missing .lgx or sidecar.json - will heal"
    return 1
  fi
}

main() {
  case "${1:-}" in -h|--help) printf '%s\n' "$USAGE"; exit 0 ;; esac
  [[ $# -ge 1 ]] || { printf '%s\n' "$USAGE" >&2; exit 2; }
  [[ -n "${GH_REPO:-}" ]] || die 'GH_REPO must be set'

  auth=()
  [[ -z "${GH_TOKEN:-}" ]] || auth=(-H "Authorization: Bearer ${GH_TOKEN}")

  local module tag
  for module in "$@"; do
    tag=$(module_tag "$module")
    if release_complete "$tag"; then
      log "SKIP ${module} (${tag}): fully published"
    else
      echo "$module"
    fi
  done
}

main "$@"
