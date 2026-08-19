#!/usr/bin/env bash

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

entries="$(git config --file .gitmodules --get-regexp 'submodule\..*\.path$' 2>/dev/null \
           | sort -k2,2 -u || true)"

if [ -z "${entries}" ]; then
  printf '[]\n'
  exit 0
fi

module_paths=()
while read -r path_key root; do
  section="${path_key%.path}"
  children="$(git config --file .gitmodules --get-all "${section}.module" 2>/dev/null || true)"

  if [ -z "${children}" ]; then
    module_paths+=("${root}")
    continue
  fi

  while IFS= read -r child; do
    if [ -z "${child}" ] || [[ "${child}" == */* ]] || [[ "${child}" == "." ]] || [[ "${child}" == ".." ]]; then
      echo "error: invalid immediate-child module '${child}' for ${root}" >&2
      exit 1
    fi
    module_paths+=("${root}/${child}")
  done <<< "${children}"
done <<< "${entries}"

printf '%s\n' "${module_paths[@]}" | sort -u | jq -R . | jq -s .
