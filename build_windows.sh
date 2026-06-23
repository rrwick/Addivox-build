#!/usr/bin/env bash

set -euo pipefail

# Build Addivox release artifacts for Windows from Git Bash.
#
# Usage:
#   ./build_windows.sh
#   ./build_windows.sh --clean
#   ./build_windows.sh --install
#
# Both full and demo variants are built as x64 Release standalone, VST3, and
# CLAP binaries. Intermediate files and logs go under build/windows-release/;
# collected artifacts go under build/dist/{full,demo}/windows/.
#
# Customer archives:
#   build/Addivox_v1.0.0_Windows.zip
#   build/AddivoxDemo_v1.0.0_Windows.zip
#
# --install copies both plugin variants into the per-user VST3 and CLAP folders.
# Normal builds never install plugins implicitly.
#
# Prerequisites: Git Bash, Visual Studio C++/MSBuild, and the VST3/CLAP SDKs
# under iPlug2/Dependencies/IPlug. Code signing and plugin validation are
# intentionally not performed yet.

BUILD_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDIVOX_REPO_DIR="${ADDIVOX_REPO_DIR:-${BUILD_REPO_DIR}/../Addivox}"
[[ -d "${ADDIVOX_REPO_DIR}/Addivox" ]] || { echo "Addivox source checkout not found: ${ADDIVOX_REPO_DIR}" >&2; exit 1; }
ADDIVOX_REPO_DIR="$(cd "${ADDIVOX_REPO_DIR}" && pwd)"

PROJECT_DIR="${ADDIVOX_REPO_DIR}/Addivox"
INSTALLATION_DOC="${ADDIVOX_REPO_DIR}/docs/docs/installation_windows.md"
BUILD_ROOT="${BUILD_REPO_DIR}/build"
WORK_ROOT="${BUILD_ROOT}/windows-release"
LOG_ROOT="${WORK_ROOT}/logs"
MSBUILD_ROOT="${WORK_ROOT}/msbuild"
PACKAGE_ROOT="${WORK_ROOT}/packages"
DIST_ROOT="${BUILD_ROOT}/dist"
ACTIVE_DIST_ROOT="${DIST_ROOT}/full/windows"

CONFIGURATION="${CONFIGURATION:-Release}"
PLATFORM="${PLATFORM:-x64}"
PLATFORM_TOOLSET="${PLATFORM_TOOLSET:-v145}"
CLEAN=0
INSTALL_PLUGINS=0
PLUG_VERSION=""
BUILD_VARIANT="full"
BUILD_BINARY_NAME="Addivox"
ADDIVOX_DEMO_VALUE=0
BUILT_VARIANTS=()
PACKAGED_ARTIFACTS=()

PROJECTS=("Addivox-app.vcxproj" "Addivox-vst3.vcxproj" "Addivox-clap.vcxproj")

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --clean      Remove existing Windows build outputs before building.
  --install    Install full and demo VST3/CLAP plugins for local testing.
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
    --clean) CLEAN=1 ;;
    --install) INSTALL_PLUGINS=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

log() { printf '\n==> %s\n' "$*"; }
fail() { echo "Error: $*" >&2; exit 1; }
require_tool() { command -v "$1" >/dev/null 2>&1 || fail "Required tool not found: $1"; }
require_file() { [[ -f "$1" ]] || fail "Required file not found: $1"; }

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
  MSBUILD="$(cygpath -u "${install_path}\\MSBuild\\Current\\Bin\\MSBuild.exe")"
  [[ -f "${MSBUILD}" ]] || fail "MSBuild.exe not found under ${install_path}"
}

read_plug_version() {
  PLUG_VERSION="$(sed -E -n 's/^[[:space:]]*#define[[:space:]]+PLUG_VERSION_STR[[:space:]]+"([^"]+)".*$/\1/p' "${PROJECT_DIR}/config.h" | head -n 1)"
  [[ -n "${PLUG_VERSION}" ]] || fail "Could not read PLUG_VERSION_STR from ${PROJECT_DIR}/config.h"
}

run_step() {
  local name="$1" log_file="$2"
  shift 2
  log "${name}"
  mkdir -p "$(dirname "${log_file}")"
  "$@" 2>&1 | sed '/icudtl\.dat not found at .*skipping\.\.\./d' | tee "${log_file}"
}

project_key() {
  case "$1" in
    Addivox-app.vcxproj) printf app ;;
    Addivox-vst3.vcxproj) printf vst3 ;;
    Addivox-clap.vcxproj) printf clap ;;
    *) fail "Unknown Visual Studio project: $1" ;;
  esac
}

run_msbuild() {
  local project_name="$1" project_dir_windows="$2" work_root_windows="$3"
  local key="$(project_key "${project_name}")"
  local project_path="${project_dir_windows}\\projects\\${project_name}"
  local variant_root="${work_root_windows}\\msbuild\\${BUILD_VARIANT}"
  local output_dir="${variant_root}\\${key}\\out"
  local intermediate_dir="${variant_root}\\${key}\\int"
  local bundle_dir="${variant_root}\\bundle"
  local disabled_install_root="${work_root_windows}\\install-disabled"

  env -u Path MSYS2_ARG_CONV_EXCL='*' "${MSBUILD}" "${project_path}" /m \
    "/p:Configuration=${CONFIGURATION}" "/p:Platform=${PLATFORM}" "/p:PlatformToolset=${PLATFORM_TOOLSET}" \
    "/p:SolutionDir=${project_dir_windows}\\" "/p:OutDir=${output_dir}\\" "/p:IntDir=${intermediate_dir}\\" \
    "/p:BUILD_DIR=${bundle_dir}" "/p:PDB_FILE=${variant_root}\\pdbs\\${BUILD_BINARY_NAME}-${key}.pdb" \
    "/p:BINARY_NAME=${BUILD_BINARY_NAME}" "/p:EXTRA_RELEASE_DEFS=ADDIVOX_DEMO=${ADDIVOX_DEMO_VALUE}" \
    "/p:VST3_X64_PATH=${disabled_install_root}\\VST3" "/p:CLAP_X64_PATH=${disabled_install_root}\\CLAP" \
    /p:COPY_VST2=0 /verbosity:minimal /nologo
}

copy_tree() {
  [[ -d "$1" ]] || fail "Expected directory not found: $1"
  rm -rf "$2"; mkdir -p "$(dirname "$2")"; cp -R "$1" "$2"
}

collect_variant_artifacts() {
  local root="${MSBUILD_ROOT}/${BUILD_VARIANT}"
  local standalone="${root}/app/out/${BUILD_BINARY_NAME}.exe"
  local vst3="${root}/bundle/${BUILD_BINARY_NAME}.vst3"
  local clap="${root}/clap/out/${BUILD_BINARY_NAME}.clap"
  local patches="${root}/app/out/factory_patches"
  require_file "${standalone}"
  require_file "${vst3}/Contents/x86_64-win/${BUILD_BINARY_NAME}.vst3"
  require_file "${clap}"

  rm -rf "${ACTIVE_DIST_ROOT}"; mkdir -p "${ACTIVE_DIST_ROOT}"
  cp "${standalone}" "${ACTIVE_DIST_ROOT}/${BUILD_BINARY_NAME}.exe"
  cp "${clap}" "${ACTIVE_DIST_ROOT}/${BUILD_BINARY_NAME}.clap"
  copy_tree "${vst3}" "${ACTIVE_DIST_ROOT}/${BUILD_BINARY_NAME}.vst3"
  copy_tree "${patches}" "${ACTIVE_DIST_ROOT}/factory_patches"

  local count
  count="$(find "${ACTIVE_DIST_ROOT}/factory_patches" -maxdepth 1 -type f -name '*.toml' | wc -l | tr -d ' ')"
  [[ "${count}" -eq 15 ]] || fail "Expected 15 ${BUILD_VARIANT} factory patches, found ${count}."
  count="$(find "${ACTIVE_DIST_ROOT}/${BUILD_BINARY_NAME}.vst3/Contents/Resources/factory_patches" -maxdepth 1 -type f -name '*.toml' | wc -l | tr -d ' ')"
  [[ "${count}" -eq 15 ]] || fail "Expected 15 ${BUILD_VARIANT} VST3 factory patches, found ${count}."
}

build_variant() {
  BUILD_VARIANT="$1"; ADDIVOX_DEMO_VALUE="$2"
  [[ "${ADDIVOX_DEMO_VALUE}" -eq 1 ]] && BUILD_BINARY_NAME="AddivoxDemo" || BUILD_BINARY_NAME="Addivox"
  ACTIVE_DIST_ROOT="${DIST_ROOT}/${BUILD_VARIANT}/windows"
  log "Building ${BUILD_VARIANT} Windows artifacts"
  local project_dir_windows="$(cygpath -w "${PROJECT_DIR}")"
  local work_root_windows="$(cygpath -w "${WORK_ROOT}")"
  local project
  for project in "${PROJECTS[@]}"; do
    run_step "${BUILD_VARIANT} ${project}" "${LOG_ROOT}/${BUILD_VARIANT}-${project%.vcxproj}.log" \
      run_msbuild "${project}" "${project_dir_windows}" "${work_root_windows}"
  done
  log "Collecting ${BUILD_VARIANT} Windows artifacts"
  collect_variant_artifacts
  BUILT_VARIANTS+=("${BUILD_VARIANT}")
}

package_windows_variant() {
  local variant="$1" binary_name="$2"
  local source_dir="${DIST_ROOT}/${variant}/windows"
  local package_name="${binary_name}_v${PLUG_VERSION}_Windows.zip"
  local package_path="${BUILD_ROOT}/${package_name}"
  local staging_dir="${PACKAGE_ROOT}/${binary_name}"
  log "Packaging ${package_name}"
  rm -rf "${staging_dir}" "${package_path}"; mkdir -p "${staging_dir}"
  sed -E 's/\[([^][]+)\]\([^)]+\)/\1/g' "${INSTALLATION_DOC}" > "${staging_dir}/README.md"
  cp "${source_dir}/${binary_name}.exe" "${source_dir}/${binary_name}.clap" "${staging_dir}/"
  cp -R "${source_dir}/${binary_name}.vst3" "${source_dir}/factory_patches" "${staging_dir}/"
  local staging_dir_windows="$(cygpath -w "${staging_dir}")"
  local package_path_windows="$(cygpath -w "${package_path}")"
  ADDIVOX_ZIP_SOURCE="${staging_dir_windows}" ADDIVOX_ZIP_DESTINATION="${package_path_windows}" powershell.exe -NoProfile -NonInteractive -Command \
    'Add-Type -AssemblyName System.IO.Compression.FileSystem; [IO.Compression.ZipFile]::CreateFromDirectory($env:ADDIVOX_ZIP_SOURCE, $env:ADDIVOX_ZIP_DESTINATION, [IO.Compression.CompressionLevel]::Optimal, $false)'
  require_file "${package_path}"
  PACKAGED_ARTIFACTS+=("${package_path}")
}

package_windows_distributables() {
  package_windows_variant full Addivox
  package_windows_variant demo AddivoxDemo
}

install_plugin_variant() {
  local variant="$1" binary_name="$2" vst3_dir="$3" clap_dir="$4"
  local source_dir="${DIST_ROOT}/${variant}/windows"
  rm -rf "${vst3_dir}/${binary_name}.vst3"
  cp -R "${source_dir}/${binary_name}.vst3" "${vst3_dir}/${binary_name}.vst3"
  cp "${source_dir}/${binary_name}.clap" "${clap_dir}/${binary_name}.clap"
  printf 'Installed %s\n' "${vst3_dir}/${binary_name}.vst3"
  printf 'Installed %s\n' "${clap_dir}/${binary_name}.clap"
}

install_plugins() {
  [[ -n "${LOCALAPPDATA:-}" ]] || fail "LOCALAPPDATA is not set."
  local local_app_data="$(cygpath -u "${LOCALAPPDATA}")"
  local vst3_dir="${local_app_data}/Programs/Common/VST3" clap_dir="${local_app_data}/Programs/Common/CLAP"
  log "Installing full and demo VST3/CLAP plugins"
  mkdir -p "${vst3_dir}" "${clap_dir}"
  install_plugin_variant full Addivox "${vst3_dir}" "${clap_dir}"
  install_plugin_variant demo AddivoxDemo "${vst3_dir}" "${clap_dir}"
  rm -rf "${clap_dir}/factory_patches"
  cp -R "${DIST_ROOT}/full/windows/factory_patches" "${clap_dir}/factory_patches"
}

print_summary() {
  printf '\n============================================================\nAddivox Windows build summary\n============================================================\n'
  printf 'Configuration: %s|%s\nToolset:       %s\nWork root:     %s\nDist root:     %s\nLogs:          %s\n' \
    "${CONFIGURATION}" "${PLATFORM}" "${PLATFORM_TOOLSET}" "${WORK_ROOT}" "${DIST_ROOT}" "${LOG_ROOT}"
  printf '\nBuilt variants: %d\n' "${#BUILT_VARIANTS[@]}"
  local item; for item in "${BUILT_VARIANTS[@]}"; do printf '  %s\n' "${DIST_ROOT}/${item}/windows"; done
  printf '\nPackaged artifacts: %d\n' "${#PACKAGED_ARTIFACTS[@]}"
  for item in "${PACKAGED_ARTIFACTS[@]}"; do printf '  %s\n' "${item}"; done
  [[ "${INSTALL_PLUGINS}" -eq 1 ]] && printf '\nPlugin install requested: yes\n' || printf '\nPlugin install requested: no. Use --install to install full and demo plugins.\n'
  printf '\nSigning status: unsigned Windows artifacts. Code signing is not implemented yet.\n'
  printf 'Validation status: plugin validators are not implemented yet.\n'
}

main() {
  require_tool cygpath; require_tool find; require_tool powershell.exe; require_tool sed; require_tool tee
  find_msbuild; read_plug_version
  require_file "${INSTALLATION_DOC}"
  require_file "${ADDIVOX_REPO_DIR}/iPlug2/Dependencies/IPlug/VST3_SDK/pluginterfaces/base/funknown.h"
  require_file "${ADDIVOX_REPO_DIR}/iPlug2/Dependencies/IPlug/CLAP_SDK/include/clap/clap.h"
  require_file "${ADDIVOX_REPO_DIR}/iPlug2/Dependencies/IPlug/CLAP_HELPERS/include/clap/helpers/plugin.hh"
  if [[ "${CLEAN}" -eq 1 ]]; then
    log "Cleaning Windows build outputs"
    rm -rf "${WORK_ROOT}" "${DIST_ROOT}/full/windows" "${DIST_ROOT}/demo/windows" || fail "Could not clean outputs. Close Addivox and REAPER, then try again."
    rm -f "${BUILD_ROOT}"/Addivox_v*_Windows.zip "${BUILD_ROOT}"/AddivoxDemo_v*_Windows.zip
  fi
  rm -rf "${DIST_ROOT}/full/windows" "${DIST_ROOT}/demo/windows" "${PACKAGE_ROOT}"
  mkdir -p "${LOG_ROOT}" "${PACKAGE_ROOT}"
  build_variant full 0
  build_variant demo 1
  package_windows_distributables
  [[ "${INSTALL_PLUGINS}" -eq 1 ]] && install_plugins
  print_summary
}

main "$@"
