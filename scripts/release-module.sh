#!/usr/bin/env bash
set -euo pipefail

USAGE="\
release-module.sh - merge / verify / sign / package ONE module.
Publishing is NOT done here - the Jenkinsfile publishes the output
directory via the status-jenkins-lib github functions.

Usage:
  release-module.sh <module-dir-name> <variants-dir> <out-base-dir>

Expects:
  - <variants-dir>/<module>__<variant>.lgx  (one per built variant)
  - submodules/<module>/metadata.json       (name+version source of truth)
  - lgx on PATH

Environment:
  LGX_SIGNING_KEY  (optional)  path to JWK secret file; unsigned if unset
  LGX_SIGNER_NAME  (optional)  self-asserted signer name, default: Logos
  LGX_SIGNER_URL   (optional)  self-asserted signer URL, default: https://logos.co

Produces <out-base-dir>/<module>/:
  - <name>-<version>.lgx    (merged, signed)
  - sidecar.json            (must keep this literal name on the release)
  - TAG                     (release tag:   <name>-v<version>)
  - NOTES                   (release description)"

usage() { printf '%s\n' "$USAGE"; }
log()   { printf '%s\n' "$*"; }
warn()  { printf 'WARNING: %s\n' "$*" >&2; }
die()   { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

cleanup() { [[ -n "${keys_tmpd:-}" ]] && rm -rf "$keys_tmpd"; }
trap cleanup EXIT

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
  keys_tmpd=$(mktemp -d)
  cp "$LGX_SIGNING_KEY" "${keys_tmpd}/release.jwk"
  chmod 600 "${keys_tmpd}/release.jwk"
  lgx sign "$out" --key release --keys-dir "$keys_tmpd" \
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

write_sidecar() {
  local sha size sig mroot built_json
  sha=$(sha256sum "$out" | awk '{print $1}')
  size=$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out")  # GNU || BSD stat
  sig=$(lgx signature "$out" 2>/dev/null || true)
  mroot=$(jq -r '.hashes.root // ""' <<<"$manifest")
  built_json=$(printf '%s' "$built_csv" | jq -R 'split(",") | map(select(length>0))')

  jq -n \
    --arg releaseTag "$tag" \
    --arg releasedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg sha "$sha" --argjson size "$size" \
    --arg rootHash "$mroot" \
    --argjson manifest "$manifest" \
    --arg signature "$sig" \
    --argjson builtVariants "$built_json" \
    '{
       publisherRef:  $releaseTag,
       releasedAt:    $releasedAt,
       sha256:        $sha,
       size:          $size,
       rootHash:      $rootHash,
       builtVariants: $builtVariants,
       manifest:      $manifest
     } + (if ($signature | length) > 0
          then { signature: ($signature | fromjson) }
          else {} end)' > "${outdir}/sidecar.json"
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
  lgx verify "$out"
  sign_package
  cross_check_manifest
  write_sidecar

  printf '%s\n' "$tag" > "${outdir}/TAG"
  printf 'Built variants: %s\n' "$built_csv" > "${outdir}/NOTES"
  log "PACKAGED ${tag} (${built_csv}) -> ${outdir}"
}

main "$@"