#!/usr/bin/env bash

set -euo pipefail

# Build Addivox standalone, VST3, and CLAP x64 Release artifacts on Windows.
# Run this script from Git Bash.

BUILD_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDIVOX_REPO_DIR="${ADDIVOX_REPO_DIR:-${BUILD_REPO_DIR}/../Addivox}"
if [[ ! -d "${ADDIVOX_REPO_DIR}/Addivox" ]]; then
  echo "Addivox source checkout not found: ${ADDIVOX_REPO_DIR}" >&2
  echo "Set ADDIVOX_REPO_DIR=/path/to/Addivox if the source repo is not next to Addivox-build." >&2
  exit 1
fi
ADDIVOX_REPO_DIR="$(cd "${ADDIVOX_REPO_DIR}" && pwd)"

PROJECT_DIR="${ADDIVOX_REPO_DIR}/Addivox"
BUILD_ROOT="${BUILD_REPO_DIR}/build"
WORK_ROOT="${BUILD_ROOT}/windows-release"
LOG_ROOT="${WORK_ROOT}/logs"
DIST_ROOT="${BUILD_ROOT}/dist/full/windows"
SOURCE_BUILD_ROOT="${PROJECT_DIR}/build-win"

CONFIGURATION="${CONFIGURATION:-Release}"
PLATFORM="${PLATFORM:-x64}"
PLATFORM_TOOLSET="${PLATFORM_TOOLSET:-v145}"
CLEAN=0
INSTALL_PLUGINS=0

PROJECTS=(
  "Addivox-app.vcxproj"
  "Addivox-vst3.vcxproj"
  "Addivox-clap.vcxproj"
)

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --clean      Remove existing Windows build outputs before building.
  --install    Install VST3 and CLAP artifacts into per-user plugin folders.
  --help       Show this help.

Environment overrides:
  ADDIVOX_REPO_DIR     Addivox source checkout (default: ../Addivox)
  CONFIGURATION        MSBuild configuration (default: Release)
  PLATFORM             MSBuild platform (default: x64)
  PLATFORM_TOOLSET     MSVC platform toolset (default: v145)
  VSWHERE              Path to vswhere.exe
  MSBUILD              Path to MSBuild.exe
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)
      CLEAN=1
      ;;
    --install)
      INSTALL_PLUGINS=1
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

log() {
  printf '\n==> %s\n' "$*"
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "Required tool not found: $1"
}

require_file() {
  [[ -f "$1" ]] || fail "Required file not found: $1"
}

find_msbuild() {
  if [[ -n "${MSBUILD:-}" ]]; then
    [[ -f "${MSBUILD}" ]] || fail "MSBUILD does not exist: ${MSBUILD}"
    return
  fi

  local vswhere="${VSWHERE:-/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe}"
  [[ -f "${vswhere}" ]] || fail "vswhere.exe not found: ${vswhere}"

  local install_path
  install_path="$("${vswhere}" -latest -products '*' -requires Microsoft.Component.MSBuild -property installationPath | tr -d '\r')"
  [[ -n "${install_path}" ]] || fail "No Visual Studio installation with MSBuild was found."

  local msbuild_windows="${install_path}\\MSBuild\\Current\\Bin\\MSBuild.exe"
  MSBUILD="$(cygpath -u "${msbuild_windows}")"
  [[ -f "${MSBUILD}" ]] || fail "MSBuild.exe not found: ${msbuild_windows}"
}

run_step() {
  local name="$1"
  local log_file="$2"
  shift 2

  log "${name}"
  mkdir -p "$(dirname "${log_file}")"
  "$@" 2>&1 | tee "${log_file}"
}

run_msbuild() {
  local project_name="$1"
  local project_dir_windows="$2"
  local work_root_windows="$3"
  local project_path="${project_dir_windows}\\projects\\${project_name}"

  # Prevent iPlug2's post-build event from implicitly installing plugins during
  # a normal build. The --install option below owns installation explicitly.
  local disabled_install_root="${work_root_windows}\\install-disabled"

  env -u Path MSYS2_ARG_CONV_EXCL='*' "${MSBUILD}" \
    "${project_path}" \
    /m \
    "/p:Configuration=${CONFIGURATION}" \
    "/p:Platform=${PLATFORM}" \
    "/p:PlatformToolset=${PLATFORM_TOOLSET}" \
    "/p:SolutionDir=${project_dir_windows}\\" \
    "/p:VST3_X64_PATH=${disabled_install_root}\\VST3" \
    "/p:CLAP_X64_PATH=${disabled_install_root}\\CLAP" \
    /p:COPY_VST2=0 \
    /verbosity:minimal \
    /nologo
}

copy_tree() {
  local source_path="$1"
  local destination_path="$2"
  [[ -d "${source_path}" ]] || fail "Expected directory not found: ${source_path}"
  rm -rf "${destination_path}"
  mkdir -p "$(dirname "${destination_path}")"
  cp -R "${source_path}" "${destination_path}"
}

collect_artifacts() {
  local standalone="${SOURCE_BUILD_ROOT}/app/${PLATFORM}/${CONFIGURATION}/Addivox.exe"
  local vst3="${SOURCE_BUILD_ROOT}/Addivox.vst3"
  local clap="${SOURCE_BUILD_ROOT}/clap/${PLATFORM}/${CONFIGURATION}/Addivox.clap"
  local patches="${SOURCE_BUILD_ROOT}/app/${PLATFORM}/${CONFIGURATION}/factory_patches"

  require_file "${standalone}"
  require_file "${vst3}/Contents/x86_64-win/Addivox.vst3"
  require_file "${clap}"

  rm -rf "${DIST_ROOT}"
  mkdir -p "${DIST_ROOT}"
  cp "${standalone}" "${DIST_ROOT}/Addivox.exe"
  cp "${clap}" "${DIST_ROOT}/Addivox.clap"
  copy_tree "${vst3}" "${DIST_ROOT}/Addivox.vst3"
  copy_tree "${patches}" "${DIST_ROOT}/factory_patches"

  local patch_count
  patch_count="$(find "${DIST_ROOT}/factory_patches" -maxdepth 1 -type f -name '*.toml' | wc -l | tr -d ' ')"
  [[ "${patch_count}" -eq 15 ]] || fail "Expected 15 factory patches, found ${patch_count}."

  local bundled_patch_count
  bundled_patch_count="$(find "${DIST_ROOT}/Addivox.vst3/Contents/Resources/factory_patches" -maxdepth 1 -type f -name '*.toml' | wc -l | tr -d ' ')"
  [[ "${bundled_patch_count}" -eq 15 ]] || fail "Expected 15 VST3 factory patches, found ${bundled_patch_count}."
}

install_plugins() {
  [[ -n "${LOCALAPPDATA:-}" ]] || fail "LOCALAPPDATA is not set."
  local local_app_data
  local_app_data="$(cygpath -u "${LOCALAPPDATA}")"
  local vst3_dir="${local_app_data}/Programs/Common/VST3"
  local clap_dir="${local_app_data}/Programs/Common/CLAP"

  log "Installing VST3 and CLAP plugins"
  mkdir -p "${vst3_dir}" "${clap_dir}"
  rm -rf "${vst3_dir}/Addivox.vst3" "${clap_dir}/factory_patches"
  cp -R "${DIST_ROOT}/Addivox.vst3" "${vst3_dir}/Addivox.vst3"
  cp "${DIST_ROOT}/Addivox.clap" "${clap_dir}/Addivox.clap"
  cp -R "${DIST_ROOT}/factory_patches" "${clap_dir}/factory_patches"

  printf 'Installed %s\n' "${vst3_dir}/Addivox.vst3"
  printf 'Installed %s\n' "${clap_dir}/Addivox.clap"
}

print_summary() {
  printf '\n'
  printf '============================================================\n'
  printf 'Addivox Windows build complete\n'
  printf '============================================================\n'
  printf 'Configuration: %s|%s\n' "${CONFIGURATION}" "${PLATFORM}"
  printf 'Toolset:       %s\n' "${PLATFORM_TOOLSET}"
  printf 'Artifacts:     %s\n' "${DIST_ROOT}"
  printf 'Logs:          %s\n' "${LOG_ROOT}"
  printf '\n'
  printf '  %s\n' "${DIST_ROOT}/Addivox.exe"
  printf '  %s\n' "${DIST_ROOT}/Addivox.vst3"
  printf '  %s\n' "${DIST_ROOT}/Addivox.clap"
  printf '  %s\n' "${DIST_ROOT}/factory_patches"
}

main() {
  require_tool cygpath
  require_tool find
  require_tool tee
  find_msbuild

  require_file "${ADDIVOX_REPO_DIR}/iPlug2/Dependencies/IPlug/VST3_SDK/pluginterfaces/base/funknown.h"
  require_file "${ADDIVOX_REPO_DIR}/iPlug2/Dependencies/IPlug/CLAP_SDK/include/clap/clap.h"
  require_file "${ADDIVOX_REPO_DIR}/iPlug2/Dependencies/IPlug/CLAP_HELPERS/include/clap/helpers/plugin.hh"

  if [[ "${CLEAN}" -eq 1 ]]; then
    log "Cleaning Windows build outputs"
    if ! rm -rf "${SOURCE_BUILD_ROOT}" "${WORK_ROOT}" "${DIST_ROOT}"; then
      fail "Could not clean Windows build outputs. Close Addivox, REAPER, and any other process using the built binaries, then try again."
    fi
  fi

  mkdir -p "${LOG_ROOT}"
  local project_dir_windows
  local work_root_windows
  project_dir_windows="$(cygpath -w "${PROJECT_DIR}")"
  work_root_windows="$(cygpath -w "${WORK_ROOT}")"

  local project
  for project in "${PROJECTS[@]}"; do
    run_step "Build ${project}" "${LOG_ROOT}/${project%.vcxproj}.log" \
      run_msbuild "${project}" "${project_dir_windows}" "${work_root_windows}"
  done

  log "Collecting Windows artifacts"
  collect_artifacts

  if [[ "${INSTALL_PLUGINS}" -eq 1 ]]; then
    install_plugins
  fi

  print_summary
}

main "$@"
