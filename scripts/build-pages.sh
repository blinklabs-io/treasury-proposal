#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="${repo_root}/docs/site"
output_dir="${repo_root}/_site"

if [[ ! -f "${source_dir}/index.html" ]]; then
  echo "missing ${source_dir}/index.html" >&2
  exit 1
fi

rm -rf "${output_dir}"
mkdir -p "${output_dir}"
cp -R "${source_dir}/." "${output_dir}/"

touch "${output_dir}/.nojekyll"

echo "GitHub Pages site generated in ${output_dir}"
