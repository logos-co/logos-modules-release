#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

USAGE="\
release-module.sh - merge, sign, upload to Logos Storage and package ONE
module for release. Publishing is done by the Jenkinsfile.

Usage:
  release-module.sh <module-dir-name> <variants-dir> <out-base-dir>

Expects:
  <variants-dir>/<module>__<variant>.lgx   one per built variant
  submodules/<module>/metadata.json        name + version

Environment (all optional):
  LGX_SIGNING_KEY      Ed25519 secret JWK file; unsigned if unset
  LGX_SIGNER_NAME      default: Logos
  LGX_SIGNER_URL       default: https://logos.co
  REQUESTED_VARIANTS   comma-separated; unbuilt ones are listed as missing
  STORAGE_NODES_TEST   comma-separated logos.test node URLs
  STORAGE_NODES_DEV    comma-separated logos.dev node URLs
  STORAGE_USER_TEST, STORAGE_PASS_TEST, STORAGE_USER_DEV, STORAGE_PASS_DEV

  Storage upload failures are never fatal.

Produces <out-base-dir>/<module>/:
  <name>-<version>.lgx, sidecar.json, TAG, TITLE, NOTES,
  STORAGE (per-network upload status, read by Jenkins)"

REQUESTED_VARIANTS=${REQUESTED_VARIANTS:-darwin-arm64,linux-amd64,linux-arm64,windows-amd64}

log()  { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
csv()  { local IFS=,; echo "$*"; }
json_array() { jq -nc '$ARGS.positional' --args "$@"; }

read_metadata() {
  local meta="submodules/${module}/metadata.json"
  [[ -f "$meta" ]] || die "no ${meta}"
  name=$(jq -er .name "$meta")   || die "${meta}: missing name"
  ver=$(jq -er .version "$meta") || die "${meta}: missing version"
  tag="${name}-v${ver}"
  out="${outdir}/${name}-${ver}.lgx"
}

merge_variants() {
  local files=("${vdir}/${module}__"*.lgx) f v
  case ${#files[@]} in
    0) die "no variants built for ${module}" ;;
    1) cp "${files[0]}" "$out" ;;
    *) lgx merge "${files[@]}" -o "$out" -y ;;
  esac
  # Copies out of /nix/store are read-only; lgx sign rewrites in place.
  chmod u+w "$out"

  built=()
  for f in "${files[@]}"; do
    f=${f##*__}
    built+=("${f%.lgx}")
  done
  missing=()
  for v in ${REQUESTED_VARIANTS//,/ }; do
    [[ " ${built[*]} " == *" ${v} "* ]] || missing+=("$v")
  done
}

sign_package() {
  if [[ -z "${LGX_SIGNING_KEY:-}" ]]; then
    warn 'LGX_SIGNING_KEY unset - packaging UNSIGNED'
    return
  fi
  lgx sign "$out" --key "$LGX_SIGNING_KEY" \
    --name "${LGX_SIGNER_NAME:-Logos}" --url "${LGX_SIGNER_URL:-https://logos.co}"
  lgx verify "$out"
}

check_manifest() {
  manifest=$(lgx manifest "$out" --json)
  local found
  found=$(jq -r '"\(.name)@\(.version)"' <<<"$manifest")
  [[ "$found" == "${name}@${ver}" ]] \
    || die "manifest drift: metadata.json ${name}@${ver} vs .lgx ${found} (bump metadata.json with the submodule)"
}

upload_storage() {
  cid=""
  networks=()
  if [[ -z "${STORAGE_NODES_TEST:-}${STORAGE_NODES_DEV:-}" ]]; then
    log 'STORAGE_NODES_TEST/DEV unset - skipping Logos Storage upload'
    return
  fi
  [[ -z "${STORAGE_NODES_TEST:-}" ]] || upload_network test "$STORAGE_NODES_TEST" "${STORAGE_USER_TEST:-}" "${STORAGE_PASS_TEST:-}"
  [[ -z "${STORAGE_NODES_DEV:-}" ]]  || upload_network dev  "$STORAGE_NODES_DEV"  "${STORAGE_USER_DEV:-}"  "${STORAGE_PASS_DEV:-}"

  if [[ ${#networks[@]} -eq 0 ]]; then
    warn 'Logos Storage upload failed on every network - releasing without cid'
  else
    log "uploaded to Logos Storage: cid=${cid} networks=$(csv "${networks[@]}")"
  fi
}

# Never fails. Writes <net>=ok|partial|failed and <net>_failed=<nodes> to STORAGE.
upload_network() {
  local net="$1" nodes="$2" user="$3" pass="$4" node got status ok=0 failed=()
  if [[ -z "$user" || -z "$pass" ]]; then
    warn "missing credentials for logos.${net}"
    echo "${net}=failed" >> "${outdir}/STORAGE"
    return
  fi

  for node in ${nodes//,/ }; do
    if got=$(curl -sS --fail-with-body --connect-timeout 30 --max-time 900 \
               -H 'Content-Type: application/octet-stream' \
               -H "Content-Disposition: attachment; filename=\"$(basename "$out")\"" \
               --data-binary @"$out" --config - \
               "${node%/}/api/storage/v1/data" 2>&1 <<<"user = \"${user}:${pass}\"") \
       && [[ "${got//[[:space:]]/}" =~ ^[A-Za-z0-9]{32,}$ ]]; then
      cid=${got//[[:space:]]/}
      ok=$((ok + 1))
    else
      warn "logos.${net}: upload to ${node} failed: ${got}"
      failed+=("$node")
    fi
  done

  if   [[ $ok -eq 0 ]];          then status=failed
  elif [[ ${#failed[@]} -gt 0 ]]; then status=partial
  else                                status=ok
  fi
  {
    echo "${net}=${status}"
    [[ ${#failed[@]} -eq 0 ]] || echo "${net}_failed=$(csv "${failed[@]}")"
  } >> "${outdir}/STORAGE"
  [[ $ok -eq 0 ]] || networks+=("logos.${net}")
}

write_sidecar() {
  jq -n \
    --arg publisherRef "$tag" \
    --arg releasedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg sha256 "$(sha256sum "$out" | cut -d' ' -f1)" \
    --argjson size "$(wc -c < "$out")" \
    --argjson manifest "$manifest" \
    --argjson builtVariants "$(json_array "${built[@]}")" \
    --argjson missingVariants "$(json_array "${missing[@]}")" \
    --arg signature "$(lgx signature "$out" 2>/dev/null || true)" \
    --arg cid "$cid" \
    --argjson networks "$(json_array "${networks[@]}")" \
    '{
       publisherRef:    $publisherRef,
       releasedAt:      $releasedAt,
       sha256:          $sha256,
       size:            $size,
       rootHash:        ($manifest.hashes.root // ""),
       builtVariants:   $builtVariants,
       missingVariants: $missingVariants,
       manifest:        $manifest
     }
     + (if $signature != "" then {signature: ($signature | fromjson)} else {} end)
     + (if $cid != "" then {cid: $cid, networks: $networks} else {} end)' \
    > "${outdir}/sidecar.json"
}

write_release_meta() {
  local built_list missing_list
  built_list=$(csv "${built[@]}")
  missing_list=$(csv "${missing[@]}")
  missing_list=${missing_list:-—}
  echo "$tag"            > "${outdir}/TAG"
  echo "${name} v${ver}" > "${outdir}/TITLE"
  printf 'Built variants: %s\nMissing variants: %s\n' \
    "${built_list//,/, }" "${missing_list//,/, }" > "${outdir}/NOTES"
}

main() {
  case "${1:-}" in -h|--help) printf '%s\n' "$USAGE"; exit 0 ;; esac
  [[ $# -eq 3 ]] || { printf '%s\n' "$USAGE" >&2; exit 1; }
  module="$1"
  vdir="$2"
  outdir="$3/${module}"
  rm -rf "$outdir"
  mkdir -p "$outdir"

  read_metadata
  merge_variants
  lgx verify "$out"
  sign_package
  check_manifest
  upload_storage
  write_sidecar
  write_release_meta

  log "PACKAGED ${tag} ($(csv "${built[@]}")) -> ${outdir}"
}

main "$@"
