#!/usr/bin/env bash
# Add a Logos module to this catalog: registers it as a git submodule
# under submodules/ and generates the matching per-module release
# workflow from .github/workflows/release-module.yml.template.
#
# Usage:
#   ./scripts/add-module.sh <git-url> [submodule-name] [branch]
#
# Examples:
#   ./scripts/add-module.sh https://github.com/me/my-cool-module
#   ./scripts/add-module.sh https://github.com/me/my-cool-module my-cool-module main
#
# After running:
#   - review `git status`
#   - commit (.gitmodules, submodules/<name>, the new workflow file)
#   - push, then trigger "Release <name>" from the Actions tab
#     (or run the umbrella "Release all modules")

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

URL="${1:-}"
if [ -z "${URL}" ]; then
  echo "usage: $0 <git-url> [submodule-name] [branch]" >&2
  exit 2
fi

# Derive a default submodule directory name from the URL basename.
NAME="${2:-}"
if [ -z "${NAME}" ]; then
  NAME="$(basename "${URL%.git}")"
fi
BRANCH="${3:-}"

PATH_REL="submodules/${NAME}"
TEMPLATE=".github/workflows/release-module.yml.template"

if [ ! -f "${TEMPLATE}" ]; then
  echo "error: ${TEMPLATE} not found — run from a fork of logos-modules-release-base" >&2
  exit 1
fi

if [ -e "${PATH_REL}" ]; then
  echo "error: ${PATH_REL} already exists" >&2
  exit 1
fi

echo "==> adding submodule ${NAME}"
if [ -n "${BRANCH}" ]; then
  git submodule add -b "${BRANCH}" "${URL}" "${PATH_REL}"
else
  git submodule add "${URL}" "${PATH_REL}"
fi

module_paths=()
if [ -f "${PATH_REL}/metadata.json" ]; then
  module_paths+=("${PATH_REL}")
else
  while IFS= read -r metadata; do
    module_paths+=("${metadata%/metadata.json}")
  done < <(find "${PATH_REL}" -mindepth 2 -maxdepth 2 -type f -name metadata.json | sort)
fi

if [ "${#module_paths[@]}" -eq 0 ]; then
  echo "error: ${PATH_REL} contains no root or immediate-child metadata.json" >&2
  exit 1
fi

workflow_names=()
workflows=()
for module_path in "${module_paths[@]}"; do
  module_name="$(jq -r '.name // empty' "${module_path}/metadata.json")"
  if [[ ! "${module_name}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "error: ${module_path}/metadata.json has an invalid module name" >&2
    exit 1
  fi
  workflow_name="${module_name}"
  if [ "${module_path}" = "${PATH_REL}" ]; then
    workflow_name="${NAME}"
  fi
  if [[ ! "${workflow_name}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "error: invalid workflow name '${workflow_name}'" >&2
    exit 1
  fi
  workflow_slug="${workflow_name//_/-}"
  workflow=".github/workflows/release-${workflow_slug}.yml"
  if [ -e "${workflow}" ]; then
    echo "error: ${workflow} already exists" >&2
    exit 1
  fi
  workflow_names+=("${workflow_name}")
  workflows+=("${workflow}")
done

for index in "${!module_paths[@]}"; do
  module_path="${module_paths[$index]}"
  workflow_name="${workflow_names[$index]}"
  workflow="${workflows[$index]}"
  echo "==> generating ${workflow}"
  sed -e "s|__MODULE__|${workflow_name}|g" \
      -e "s|__MODULE_PATH__|${module_path}|g" \
      "${TEMPLATE}" > "${workflow}"

  if [ "${module_path}" != "${PATH_REL}" ]; then
    child="${module_path#"${PATH_REL}/"}"
    git config --file .gitmodules --add "submodule.${PATH_REL}.module" "${child}"
  fi
done

cat <<EOF

Done. Next:

  git add .gitmodules "${PATH_REL}" ${workflows[*]}
  git commit -m "Add ${NAME}"
  git push

Then publish it:
  - Actions tab → run the generated per-module workflow
  - or run "Release all modules" to (re)publish everything

A new release is cut whenever you bump the submodule pointer
(and thereby its metadata.json#version) and re-run the workflow.
EOF
