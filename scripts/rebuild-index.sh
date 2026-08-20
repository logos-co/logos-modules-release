#!/usr/bin/env bash
set -euo pipefail

USAGE="\
rebuild-index.sh - produce an updated index.json from freshly
packaged modules. Publishing (uploading index.json to the rolling
'index' release) is NOT done here - the Jenkinsfile does it via the
status-jenkins-lib github functions.

IMPORTANT ORDERING: run this AFTER the per-module releases are
published - index entries point at the release-asset URLs and
clients resolve them directly.

Usage:
  rebuild-index.sh <released-base-dir> [output-index.json]

<released-base-dir> holds <module>/ dirs from release-module.sh
(each with <name>-<version>.lgx + TAG). Uses index.py's
--with-local upload-then-index flow: URL is indexed, metadata is
read from the local file, nothing is re-downloaded. Dedupe on
(version, rootHash) makes re-runs a no-op.

Environment:
  GH_REPO         (required)  e.g. logos-co/logos-modules-release
  INDEX_TOOL_REF  (optional)  release-tool git ref, default pinned in script"

INDEX_TOOL_REPO='https://github.com/logos-co/logos-modules-release-tool'
INDEX_TOOL_REF="${INDEX_TOOL_REF:-main}"  # TODO: pin to a tag/SHA once release-tool tags versions

usage() { printf '%s\n' "$USAGE"; }
log()   { printf '%s\n' "$*"; }
warn()  { printf 'WARNING: %s\n' "$*" >&2; }
die()   { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

fetch_current_index() {
  local url="https://github.com/${GH_REPO}/releases/download/index/index.json"
  local http_code
  http_code=$(curl -sSL --retry 3 -o "$out_index" -w '%{http_code}' "$url") || \
    die "fetching ${url} failed (network error)"
  case "$http_code" in
    200) log "Fetched current index.json from ${url}" ;;
    404) log 'No existing index.json (first run) - starting fresh'
         rm -f "$out_index" ;;
    *)   die "fetching ${url} returned HTTP ${http_code} - refusing to rebuild from scratch" ;;
  esac
}

index_module_dir() {
  local moddir="$1" tag lgx_file fname url
  tag=$(<"${moddir}/TAG")
  lgx_file=$(find "$moddir" -maxdepth 1 -name '*.lgx' | head -n1)
  [[ -n "$lgx_file" ]] || { warn "no .lgx in ${moddir}, skipping"; return 1; }
  fname=$(basename "$lgx_file")
  url="https://github.com/${GH_REPO}/releases/download/${tag}/${fname}"

  if [[ -f "$out_index" ]]; then
    python3 "$idx" add "$out_index" --with-local "$url" "$lgx_file"
  else
    printf '%s %s\n' "$url" "$lgx_file" > "${tool_dir}/urls.txt"
    python3 "$idx" build "${tool_dir}/urls.txt" -o "$out_index"
  fi
}

main() {
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
  esac
  [[ $# -ge 1 ]] || { usage >&2; exit 1; }
  : "${GH_REPO:?GH_REPO must be set (e.g. logos-co/logos-modules-release)}"
  released_base="$1"
  out_index="${2:-index.json}"
  [[ -d "$released_base" ]] || die "not a directory: ${released_base}"

  tool_dir=$(mktemp -d)
  trap 'rm -rf "$tool_dir"' EXIT
  git clone --quiet --depth 1 --branch "$INDEX_TOOL_REF" "$INDEX_TOOL_REPO" "${tool_dir}/tool"
  idx="${tool_dir}/tool/index.py"

  fetch_current_index

  local processed=0
  for moddir in "$released_base"/*/; do
    [[ -d "$moddir" ]] || continue
    index_module_dir "$moddir" && processed=$((processed + 1))
  done

  if [[ "$processed" -eq 0 ]]; then
    log 'No packaged modules to index - nothing to do.'
    exit 0
  fi

  python3 "$idx" validate "$out_index"
  python3 "$idx" list "$out_index"
  log "Updated ${out_index} from ${processed} package(s) - ready to upload"
}

main "$@"