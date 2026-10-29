#!/usr/bin/env bash
set -euo pipefail

USAGE="\
release-module.sh - merge / verify / sign / upload / package ONE module.
Publishing is NOT done here - the Jenkinsfile publishes the output
directory via the status-jenkins-lib github functions.

Usage:
  release-module.sh <module-dir-name> <variants-dir> <out-base-dir>

Expects:
  - <variants-dir>/<module>__<variant>.lgx  (one per built variant)
  - submodules/<module>/metadata.json       (name+version source of truth)
  - lgx on PATH (with path support in 'lgx sign --key')

Environment:
  LGX_SIGNING_KEY     (optional)  path to the Ed25519 secret JWK file
                                  (any filename); unsigned if unset
  LGX_SIGNER_NAME     (optional)  self-asserted signer name, default: Logos
  LGX_SIGNER_URL      (optional)  self-asserted signer URL, default: https://logos.co
  REQUESTED_VARIANTS  (optional)  comma-separated variants the catalog builds;
                                  any not built for this module are listed as
                                  missing, default:
                                  darwin-arm64,linux-amd64,linux-arm64,windows-amd64
  STORAGE_NODES_TEST  (optional)  comma-separated logos.test node base URLs
  STORAGE_NODES_DEV   (optional)  comma-separated logos.dev node base URLs;
                                  both unset = skip the storage upload.
                                  Upload failures are never fatal.
  STORAGE_USER_TEST / STORAGE_PASS_TEST   basic auth for logos.test
  STORAGE_USER_DEV  / STORAGE_PASS_DEV    basic auth for logos.dev

Produces <out-base-dir>/<module>/:
  - <name>-<version>.lgx    (merged, signed, uploaded to storage)
  - sidecar.json            (must keep this literal name on the release;
                             carries cid + networks when storage upload succeeded)
  - TAG                     (release tag:    <name>-v<version>)
  - TITLE                   (release title:  <name> v<version>)
  - NOTES                   (release description: built vs requested variants)
  - STORAGE                 (per-network upload status + failed nodes, read by Jenkins)"

usage() { printf '%s\n' "$USAGE"; }
log()   { printf '%s\n' "$*"; }
warn()  { printf 'WARNING: %s\n' "$*" >&2; }
die()   { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Appends key=value to <outdir>/STORAGE (read by Jenkins via readProperties).
set_storage() { printf '%s=%s\n' "$1" "$2" >> "${outdir}/STORAGE"; }

read_metadata() {
  local meta="submodules/${module}/metadata.json"
  [[ -f "$meta" ]] || die "no metadata.json for ${module}"
  name=$(jq -r '.name' "$meta")
  ver=$(jq -r '.version' "$meta")
  [[ -n "$name" && "$name" != "null" ]] || die "metadata.json missing name"
  [[ -n "$ver"  && "$ver"  != "null" ]] || die "metadata.json missing version"
  tag="${name}-v${ver}"
  out="${outdir}/${name}-${ver}.lgx"
}

merge_variants() {
  mapfile -t variants < <(find "$vdir" -type f -name "${module}__*.lgx" | sort)
  case ${#variants[@]} in
    0)
      die "no variants built for ${module}"
      ;;
    1)
      log "NOTICE: single variant for ${module}; skipping merge"
      cp "${variants[0]}" "$out"
      ;;
    *)
      lgx merge "${variants[@]}" -o "$out" -y
      ;;
  esac

  # Variants copied out of /nix/store are read-only (444) and cp
  # preserves that; lgx sign rewrites the package in place.
  chmod u+w "$out"

  local f b
  built_csv=$(for f in "${variants[@]}"; do
    b=$(basename "$f" .lgx)
    printf '%s\n' "${b#"${module}"__}"
  done | sort -u | paste -sd, -)
}

sign_package() {
  if [[ -z "${LGX_SIGNING_KEY:-}" ]]; then
    warn 'LGX_SIGNING_KEY unset - packaging UNSIGNED'
    return 0
  fi
  [[ -f "$LGX_SIGNING_KEY" ]] || die "signing key file not found: ${LGX_SIGNING_KEY}"
  lgx sign "$out" --key "$LGX_SIGNING_KEY" \
    --name "${LGX_SIGNER_NAME:-Logos}" --url "${LGX_SIGNER_URL:-https://logos.co}"
  lgx verify "$out"
}

cross_check_manifest() {
  manifest=$(lgx manifest "$out" --json)
  local mname mver
  mname=$(jq -r .name    <<<"$manifest")
  mver=$(jq  -r .version <<<"$manifest")
  if [[ "$mname" != "$name" || "$mver" != "$ver" ]]; then
    printf 'ERROR: manifest drift - metadata.json %s@%s vs .lgx %s@%s\n' \
      "$name" "$ver" "$mname" "$mver" >&2
    die '(bump metadata.json when bumping the submodule)'
  fi
}

# Uploads the signed package to Logos Storage. Never fatal - Logos Storage
# isn't stable enough to block a release. A network goes into the sidecar
# only if at least one of its nodes accepted the upload; if none did, the
# sidecar has no cid/networks. Status per network goes to <outdir>/STORAGE.
upload_storage() {
  cid=""
  networks_json='[]'
  if [[ -z "${STORAGE_NODES_TEST:-}" && -z "${STORAGE_NODES_DEV:-}" ]]; then
    log 'STORAGE_NODES_TEST/STORAGE_NODES_DEV unset - skipping Logos Storage upload'
    return 0
  fi
  local networks=()
  if [[ -n "${STORAGE_NODES_TEST:-}" ]] && upload_network test "$STORAGE_NODES_TEST" \
       "${STORAGE_USER_TEST:-}" "${STORAGE_PASS_TEST:-}"; then
    networks+=('logos.test')
  fi
  if [[ -n "${STORAGE_NODES_DEV:-}" ]] && upload_network dev "$STORAGE_NODES_DEV" \
       "${STORAGE_USER_DEV:-}" "${STORAGE_PASS_DEV:-}"; then
    networks+=('logos.dev')
  fi
  if [[ ${#networks[@]} -eq 0 ]]; then
    warn 'Logos Storage upload failed on every network - releasing without cid'
    return 0
  fi
  networks_json=$(printf '%s\n' "${networks[@]}" | jq -Rc . | jq -sc .)
  log "uploaded to Logos Storage: cid=${cid} networks=$(IFS=,; echo "${networks[*]}")"
}

# Uploads $out to every node of logos.<net>. Never fatal: records
# <net>=ok|partial|failed and <net>_failed=<urls>, returns 1 if no node
# accepted it. Storage is content-addressed, so any node's CID is the CID.
upload_network() {
  local net="$1" urls="$2" user="$3" pass="$4"
  local fname endpoint got ok=0 total=0 failed=()
  fname=$(basename "$out")
  if [[ -z "$user" || -z "$pass" ]]; then
    warn "missing credentials for logos.${net}"
    set_storage "$net" failed
    return 1
  fi
  for endpoint in ${urls//,/ }; do
    total=$((total + 1))
    if ! got=$(curl -sS --fail-with-body -X POST \
                 --connect-timeout 30 --max-time 900 \
                 -H 'Content-Type: application/octet-stream' \
                 -H "Content-Disposition: attachment; filename=\"${fname}\"" \
                 --data-binary @"$out" \
                 --config - \
                 "${endpoint%/}/api/storage/v1/data" 2>&1 \
                 <<<"user = \"${user}:${pass}\""); then
      warn "storage node refused the upload (logos.${net}: ${endpoint}): ${got}"
      failed+=("$endpoint")
      continue
    fi
    got="${got//[$'\r\n\t ']/}"
    if [[ ! "$got" =~ ^[A-Za-z0-9]{32,}$ ]]; then
      warn "storage node ${endpoint} returned a malformed CID: '${got}'"
      failed+=("$endpoint")
      continue
    fi
    cid="$got"
    ok=$((ok + 1))
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    set_storage "${net}_failed" "$(IFS=,; echo "${failed[*]}")"
  fi
  if [[ "$ok" -eq 0 ]]; then
    warn "failed to upload ${fname} to every logos.${net} node"
    set_storage "$net" failed
    return 1
  fi
  if [[ "$ok" -eq "$total" ]]; then
    set_storage "$net" ok
  else
    set_storage "$net" partial
  fi
}

write_sidecar() {
  local sha size sig mroot requested built_json missing_json
  sha=$(sha256sum "$out" | awk '{print $1}')
  size=$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out")  # GNU || BSD stat
  sig=$(lgx signature "$out" 2>/dev/null || true)
  mroot=$(jq -r '.hashes.root // ""' <<<"$manifest")
  requested="${REQUESTED_VARIANTS:-darwin-arm64,linux-amd64,linux-arm64,windows-amd64}"
  built_json=$(printf '%s' "$built_csv" | jq -R 'split(",") | map(select(length>0))')
  missing_json=$(jq -cn \
    --argjson r "$(printf '%s' "$requested" | jq -R 'split(",")')" \
    --argjson b "$built_json" '$r - $b')

  jq -n \
    --arg releaseTag "$tag" \
    --arg releasedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg sha "$sha" --argjson size "$size" \
    --arg rootHash "$mroot" \
    --argjson manifest "$manifest" \
    --arg signature "$sig" \
    --arg cid "${cid:-}" \
    --argjson networks "${networks_json:-[]}" \
    --argjson builtVariants "$built_json" \
    --argjson missingVariants "$missing_json" \
    '{
       publisherRef:    $releaseTag,
       releasedAt:      $releasedAt,
       sha256:          $sha,
       size:            $size,
       rootHash:        $rootHash,
       builtVariants:   $builtVariants,
       missingVariants: $missingVariants,
       manifest:        $manifest
     } + (if ($signature | length) > 0
          then { signature: ($signature | fromjson) }
          else {} end)
       + (if ($cid | length) > 0
          then { cid: $cid, networks: $networks }
          else {} end)' > "${outdir}/sidecar.json"
}

write_release_meta() {
  local requested="${REQUESTED_VARIANTS:-darwin-arm64,linux-amd64,linux-arm64,windows-amd64}"
  local missing_csv missing_display
  missing_csv=$(comm -23 \
    <(tr ',' '\n' <<<"$requested" | sort -u) \
    <(tr ',' '\n' <<<"$built_csv" | sort -u) \
    | paste -sd, -)
  missing_display="${missing_csv:-—}"

  printf '%s\n' "$tag"             > "${outdir}/TAG"
  printf '%s v%s\n' "$name" "$ver" > "${outdir}/TITLE"
  {
    printf 'Built variants: %s\n'   "${built_csv//,/, }"
    printf 'Missing variants: %s\n' "${missing_display//,/, }"
  } > "${outdir}/NOTES"
}

main() {
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
  esac
  [[ $# -eq 3 ]] || { usage >&2; exit 1; }
  module="$1"
  vdir="$2"
  outdir="$3/${module}"
  [[ -d "$vdir" ]] || die "not a directory: ${vdir}"
  rm -rf "$outdir"
  mkdir -p "$outdir"

  read_metadata
  merge_variants
  lgx verify "$out"        # pre-sign structural check
  sign_package             # signs + re-verifies, or warns if keyless
  cross_check_manifest
  upload_storage           # before the sidecar - the CID goes into it
  write_sidecar
  write_release_meta

  log "PACKAGED ${tag} (${built_csv}) -> ${outdir}"
}

main "$@"
