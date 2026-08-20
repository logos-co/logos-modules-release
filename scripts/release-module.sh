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
  - lgx on PATH (with path support in 'lgx sign --key')

Environment:
  LGX_SIGNING_KEY     (optional)  path to the Ed25519 secret JWK file
                                  (any filename); unsigned if unset
  LGX_SIGNER_NAME     (optional)  self-asserted signer name, default: Logos
  LGX_SIGNER_URL      (optional)  self-asserted signer URL, default: https://logos.co
  REQUESTED_VARIANTS  (optional)  comma-separated variants the pipeline builds,
                                  default: darwin-arm64,linux-amd64,linux-arm64

Produces <out-base-dir>/<module>/:
  - <name>-<version>.lgx    (merged, signed)
  - sidecar.json            (must keep this literal name on the release)
  - TAG                     (release tag:    <name>-v<version>)
  - TITLE                   (release title:  <name> v<version>)
  - NOTES                   (release description: built vs requested variants)"

usage() { printf '%s\n' "$USAGE"; }
log()   { printf '%s\n' "$*"; }
warn()  { printf 'WARNING: %s\n' "$*" >&2; }
die()   { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

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

write_release_meta() {
  local requested="${REQUESTED_VARIANTS:-darwin-arm64,linux-amd64,linux-arm64}"
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
    if [[ -n "$missing_csv" ]]; then
      printf '\n_Partial release - some requested variants did not build._\n'
    fi
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
  write_sidecar
  write_release_meta

  log "PACKAGED ${tag} (${built_csv}) -> ${outdir}"
}

main "$@"