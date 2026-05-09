#!/usr/bin/env bash

set -euo pipefail

# Build the public Addivox documentation into this private build repository.
#
# The documentation source lives in ../Addivox/docs. Generated files are written
# to ./docs so this repo can own release/distribution-specific documentation
# artifacts without moving the public source files.

BUILD_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDIVOX_REPO_DIR="${ADDIVOX_REPO_DIR:-${BUILD_REPO_DIR}/../Addivox}"
if [[ ! -f "${ADDIVOX_REPO_DIR}/docs/mkdocs.yml" ]]; then
  echo "Addivox docs source not found: ${ADDIVOX_REPO_DIR}/docs/mkdocs.yml" >&2
  echo "Set ADDIVOX_REPO_DIR=/path/to/Addivox if the source repo is not next to Addivox-build." >&2
  exit 1
fi
ADDIVOX_REPO_DIR="$(cd "${ADDIVOX_REPO_DIR}" && pwd)"

MKDOCS="${MKDOCS:-mkdocs}"
DOCS_CONFIG="${ADDIVOX_REPO_DIR}/docs/mkdocs.yml"
DOCS_OUTPUT_DIR="${BUILD_REPO_DIR}/docs"

if ! command -v "${MKDOCS}" >/dev/null 2>&1; then
  echo "mkdocs command not found: ${MKDOCS}" >&2
  echo "Install MkDocs, or set MKDOCS=/path/to/mkdocs." >&2
  exit 1
fi

echo "Building Addivox docs..."
echo "  source: ${DOCS_CONFIG}"
echo "  output: ${DOCS_OUTPUT_DIR}"

"${MKDOCS}" build --clean --config-file "${DOCS_CONFIG}" --site-dir "${DOCS_OUTPUT_DIR}"

echo "Docs built successfully."
