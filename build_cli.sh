#!/usr/bin/env bash

set -euo pipefail

# Build only the Addivox command-line renderer.
#
# Output stays in the CMake build directory:
#
#   build_cli/addivox
#
# The source repository is expected to live next to this repository as ../Addivox.
# Override with ADDIVOX_REPO_DIR=/path/to/Addivox if needed.

BUILD_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDIVOX_REPO_DIR="${ADDIVOX_REPO_DIR:-${BUILD_REPO_DIR}/../Addivox}"
if [[ ! -d "${ADDIVOX_REPO_DIR}/Addivox" ]]; then
  echo "Addivox source checkout not found: ${ADDIVOX_REPO_DIR}" >&2
  echo "Set ADDIVOX_REPO_DIR=/path/to/Addivox if the source repo is not next to Addivox-build." >&2
  exit 1
fi
ADDIVOX_REPO_DIR="$(cd "${ADDIVOX_REPO_DIR}" && pwd)"
PROJECT_DIR="${ADDIVOX_REPO_DIR}/Addivox"
IPLUG2_DIR="${ADDIVOX_REPO_DIR}/iPlug2"

CONFIGURATION="${CONFIGURATION:-Release}"
CMAKE_BUILD_DIR="${BUILD_REPO_DIR}/build_cli"
CLEAN=0

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --clean    Remove ${CMAKE_BUILD_DIR} before building.
  --help     Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)
      CLEAN=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required tool not found: $1" >&2
    exit 1
  fi
}

log() {
  printf '\n==> %s\n' "$*"
}

require_tool cmake

if [[ "${CLEAN}" -eq 1 ]]; then
  log "Cleaning CLI build outputs"
  rm -rf "${CMAKE_BUILD_DIR}"
fi

log "Configuring CLI with CMake"
cmake \
  -S "${PROJECT_DIR}" \
  -B "${CMAKE_BUILD_DIR}" \
  -DCMAKE_BUILD_TYPE="${CONFIGURATION}" \
  -DADDIVOX_DEMO=OFF \
  -DIPLUG2_DIR="${IPLUG2_DIR}"

log "Building CLI"
cmake \
  --build "${CMAKE_BUILD_DIR}" \
  --config "${CONFIGURATION}" \
  --target addivox-cli

log "Built ${CMAKE_BUILD_DIR}/addivox"
