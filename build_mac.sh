#!/usr/bin/env bash

set -u
set -o pipefail

# Build Addivox release artifacts for macOS, iOS devices, iOS simulators, Xcode
# archives, and the CLI.
#
# How to run:
#
#   sudo ./build_mac.sh
#   sudo ./build_mac.sh --clean
#   sudo ./build_mac.sh --install
#   sudo ./build_mac.sh --sign_and_notarize
#
# Use sudo because the Xcode archive action currently runs an install-style
# postprocessing step that tries to set archived product ownership to root:admin.
# The non-archive build steps do not need sudo, but this script always includes
# archives so one sudo invocation is the simplest reliable path.
#
# Expect the full build to take a few minutes. All logs go under:
#
#   build/mac-release/logs/
#
# Main outputs are copied into build/dist/full and build/dist/demo:
#
#   build/dist/full/macos/Addivox.app
#     Standalone macOS app bundle.
#
#   build/dist/full/macos/Addivox.component
#     Audio Unit v2 plugin bundle for macOS DAWs.
#
#   build/dist/full/macos/Addivox.vst
#     VST2 plugin bundle for macOS hosts that still support VST2.
#
#   build/dist/full/macos/Addivox.vst3
#     VST3 plugin bundle for macOS hosts.
#
#   build/dist/full/macos/Addivox.clap
#     CLAP plugin bundle for macOS hosts.
#
#   build/dist/ios-device/
#     iOS device Release products, including Addivox.app,
#     AddivoxAppExtension.appex, and AUv3Framework.framework where produced by
#     the Xcode schemes.
#
#   build/dist/ios-simulator/
#     iOS simulator Release products for local testing.
#
#   build/dist/archives/macos/macOS-APP with AUv3.xcarchive
#     macOS app archive with the AUv3 extension included, suitable for later Mac
#     App Store export or Developer ID signing/notarization work.
#
#   build/dist/archives/ios/iOS-APP with AUv3.xcarchive
#     iOS app archive with the AUv3 extension included, suitable for later App
#     Store/TestFlight export work.
#
#   build/dist/cli/addivox
#     Release CLI executable.
#
# Customer distribution zips are written to build/:
#
#   build/Addivox_v1.0.0_macOS.zip
#   build/AddivoxDemo_v1.0.0_macOS.zip
#
# Optional local plugin install:
#
#   sudo ./build_mac.sh --install
#
# This copies macOS plugin bundles from build/dist/full/macos and
# build/dist/demo/macos into the per-user plugin
# folders under ~/Library/Audio/Plug-Ins for local DAW testing.
#
# Direct macOS distribution signing/notarization:
#
#   sudo ./build_mac.sh --sign_and_notarize
#
# This signs and notarizes the full and demo macOS app/plugin bundles before
# creating the customer zips. Signing credentials are intentionally not stored in
# the repo. Defaults can be overridden in the environment:
#
#   DEVELOPER_ID_APPLICATION='Developer ID Application: Example (TEAMID)'
#   NOTARY_PROFILE='addivox-notary'

BUILD_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDIVOX_REPO_DIR="${ADDIVOX_REPO_DIR:-${BUILD_REPO_DIR}/../Addivox}"
if [[ ! -d "${ADDIVOX_REPO_DIR}/Addivox" ]]; then
  echo "Addivox source checkout not found: ${ADDIVOX_REPO_DIR}" >&2
  echo "Set ADDIVOX_REPO_DIR=/path/to/Addivox if the source repo is not next to Addivox-build." >&2
  exit 1
fi
ADDIVOX_REPO_DIR="$(cd "${ADDIVOX_REPO_DIR}" && pwd)"
PROJECT_DIR="${ADDIVOX_REPO_DIR}/Addivox"
MAC_PROJECT="${PROJECT_DIR}/projects/Addivox-macOS.xcodeproj"
IOS_PROJECT="${PROJECT_DIR}/projects/Addivox-iOS.xcodeproj"
MACOS_INSTALLATION_DOC="${ADDIVOX_REPO_DIR}/docs/docs/installation_macos.md"

BUILD_ROOT="${BUILD_REPO_DIR}/build"
WORK_ROOT="${BUILD_ROOT}/mac-release"
DIST_ROOT="${BUILD_ROOT}/dist"
ACTIVE_DIST_ROOT="${DIST_ROOT}/full"
LOG_ROOT="${WORK_ROOT}/logs"
ARCHIVE_ROOT="${WORK_ROOT}/archives"
XCODE_DERIVED_ROOT="${WORK_ROOT}/xcode-derived"
CMAKE_BUILD_DIR="${WORK_ROOT}/cli-cmake"
PACKAGE_ROOT="${WORK_ROOT}/packages"
NOTARY_ROOT="${WORK_ROOT}/notary"

CONFIGURATION="Release"
INSTALL_PLUGINS=0
CLEAN=0
SIGN_AND_NOTARIZE=0
BUILD_VARIANT="full"
BUILD_BINARY_NAME="Addivox"
BUILD_CLI_NAME="addivox"
ADDIVOX_DEMO_VALUE=0
PLUG_VERSION=""
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-Developer ID Application: RYAN ROBERT WICK (53B4QNBZK6)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-addivox-notary}"
ADDIVOX_DEVELOPMENT_TEAM="${ADDIVOX_DEVELOPMENT_TEAM:-53B4QNBZK6}"

MAC_SCHEMES=(
  "macOS-APP"
  "macOS-APP with AUv3"
  "macOS-AUv2"
  "macOS-AUv3"
  "macOS-AUv3Framework"
  "macOS-VST2"
  "macOS-VST3"
  "macOS-CLAP"
)

IOS_SCHEMES=(
  "iOS-APP with AUv3"
  "iOS-AUv3"
  "iOS-AUv3Framework"
)

ARCHIVE_SCHEMES_MAC=(
  "macOS-APP with AUv3"
)

ARCHIVE_SCHEMES_IOS=(
  "iOS-APP with AUv3"
)

OK_STEPS=()
FAILED_STEPS=()
COPIED_ARTIFACTS=()
PACKAGED_ARTIFACTS=()

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --install        Copy built macOS plugin bundles to local user plugin folders for testing.
  --clean          Remove ${BUILD_ROOT} before building.
  --sign_and_notarize
                   Developer ID sign, notarize, and staple macOS app/plugin bundles
                   before creating customer zips. Requires local Apple credentials.
  --help           Show this help.

Archives are always built. Run this script with sudo because Xcode's archive
postprocessing currently needs permission to set archived product ownership.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      INSTALL_PLUGINS=1
      ;;
    --clean)
      CLEAN=1
      ;;
    --sign_and_notarize)
      SIGN_AND_NOTARIZE=1
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

record_ok() {
  OK_STEPS+=("$1")
}

record_fail() {
  FAILED_STEPS+=("$1")
}

run_step() {
  local name="$1"
  local log_file="$2"
  shift 2

  log "${name}"
  mkdir -p "$(dirname "${log_file}")"

  if "$@" 2>&1 | tee "${log_file}"; then
    record_ok "${name}"
    return 0
  fi

  record_fail "${name} (see ${log_file})"
  return 1
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required tool not found: $1" >&2
    exit 1
  fi
}

safe_name() {
  printf '%s' "$1" | tr '/ .' '___'
}

require_signing_prerequisites() {
  require_tool codesign
  require_tool security
  require_tool ditto
  require_tool xcrun
  require_tool spctl

  local identity_found=0
  if security find-identity -v -p codesigning | grep -F "\"${DEVELOPER_ID_APPLICATION}\"" >/dev/null; then
    identity_found=1
  elif [[ "$(id -u)" -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]] &&
      sudo -u "${SUDO_USER}" security find-identity -v -p codesigning | grep -F "\"${DEVELOPER_ID_APPLICATION}\"" >/dev/null; then
    identity_found=1
  fi

  if [[ "${identity_found}" -ne 1 ]]; then
    echo "Developer ID signing identity not found: ${DEVELOPER_ID_APPLICATION}" >&2
    echo "Override with DEVELOPER_ID_APPLICATION='Developer ID Application: Name (TEAMID)' if needed." >&2
    exit 1
  fi

  if ! xcrun notarytool --help >/dev/null 2>&1; then
    echo "xcrun notarytool is not available." >&2
    exit 1
  fi

  if ! xcrun -f stapler >/dev/null 2>&1; then
    echo "xcrun stapler is not available." >&2
    exit 1
  fi
}

run_notarytool_submit() {
  local label="$1"
  local log_file="$2"
  local zip_path="$3"

  if [[ "$(id -u)" -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    run_step "${label}" "${log_file}" \
      sudo \
        -u "${SUDO_USER}" \
        xcrun \
        notarytool \
        submit \
        "${zip_path}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait
  else
    run_step "${label}" "${log_file}" \
      xcrun \
        notarytool \
        submit \
        "${zip_path}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait
  fi
}

sign_bundle() {
  local bundle_path="$1"
  local label="$2"
  local safe_label
  safe_label="$(safe_name "${label}")"

  local nested_index=0
  while IFS= read -r -d '' nested_bundle; do
    [[ "${nested_bundle}" == "${bundle_path}" ]] && continue

    nested_index=$((nested_index + 1))
    run_step "Sign ${label} nested $(basename "${nested_bundle}")" "${LOG_ROOT}/sign-${safe_label}-nested-${nested_index}.log" \
      codesign \
        --force \
        --timestamp \
        --options runtime \
        --sign "${DEVELOPER_ID_APPLICATION}" \
        "${nested_bundle}" || return 1
  done < <(find "${bundle_path}" -depth -type d \( -name "*.appex" -o -name "*.framework" \) -print0)

  run_step "Sign ${label}" "${LOG_ROOT}/sign-${safe_label}.log" \
    codesign \
      --force \
      --timestamp \
      --options runtime \
      --sign "${DEVELOPER_ID_APPLICATION}" \
      "${bundle_path}" || return 1

  run_step "Verify signature ${label}" "${LOG_ROOT}/verify-signature-${safe_label}.log" \
    codesign \
      --verify \
      --deep \
      --strict \
      --verbose=2 \
      "${bundle_path}"
}

notarize_zip() {
  local label="$1"
  local zip_path="$2"
  local safe_label
  safe_label="$(safe_name "${label}")"

  run_notarytool_submit "Notarize ${label}" "${LOG_ROOT}/notarize-${safe_label}.log" "${zip_path}" || return 1
}

staple_bundle() {
  local bundle_path="$1"
  local label="$2"
  local safe_label
  safe_label="$(safe_name "${label}")"

  run_step "Staple ${label}" "${LOG_ROOT}/staple-${safe_label}.log" \
    xcrun \
      stapler \
      staple \
      "${bundle_path}" || return 1

  run_step "Validate staple ${label}" "${LOG_ROOT}/validate-staple-${safe_label}.log" \
    xcrun \
      stapler \
      validate \
      "${bundle_path}"
}

assess_app_bundle() {
  local app_path="$1"
  local label="$2"
  local safe_label
  safe_label="$(safe_name "${label}")"

  run_step "Assess Gatekeeper ${label}" "${LOG_ROOT}/spctl-${safe_label}.log" \
    spctl \
      --assess \
      --type execute \
      --verbose=4 \
      "${app_path}"
}

sign_and_notarize_macos_variant() {
  local variant="$1"
  local binary_name="$2"
  local source_dir="${DIST_ROOT}/${variant}/macos"
  local safe_variant
  local notary_staging_dir
  local notary_zip
  local artifact_names=(
    "${binary_name}.app"
    "${binary_name}.component"
    "${binary_name}.vst"
    "${binary_name}.vst3"
    "${binary_name}.clap"
  )
  safe_variant="$(safe_name "${variant}-${binary_name}")"
  notary_staging_dir="${NOTARY_ROOT}/${safe_variant}"
  notary_zip="${NOTARY_ROOT}/${safe_variant}.zip"

  log "Signing and notarizing ${variant} macOS app/plugin bundles"
  mkdir -p "${NOTARY_ROOT}"
  rm -rf "${notary_staging_dir}" "${notary_zip}"
  mkdir -p "${notary_staging_dir}"

  local artifact_name
  for artifact_name in "${artifact_names[@]}"; do
    local artifact_path="${source_dir}/${artifact_name}"
    local label="${variant} ${artifact_name}"

    if [[ -e "${artifact_path}" ]]; then
      sign_bundle "${artifact_path}" "${label}" || return 1
      cp -R "${artifact_path}" "${notary_staging_dir}/${artifact_name}"
    else
      record_fail "Sign/notarize ${label} (${artifact_path} not found)"
      return 1
    fi
  done

  run_step "Create notarization zip ${variant} macOS bundles" "${LOG_ROOT}/notary-zip-${safe_variant}.log" \
    ditto \
      -c \
      -k \
      --keepParent \
      "${notary_staging_dir}" \
      "${notary_zip}" || return 1

  notarize_zip "${variant} macOS bundles" "${notary_zip}" || return 1

  for artifact_name in "${artifact_names[@]}"; do
    local artifact_path="${source_dir}/${artifact_name}"
    local label="${variant} ${artifact_name}"

    staple_bundle "${artifact_path}" "${label}" || return 1

    if [[ "${artifact_name}" == *.app ]]; then
      assess_app_bundle "${artifact_path}" "${label}" || return 1
    fi
  done

}

sign_and_notarize_macos_distributables() {
  require_signing_prerequisites
  sign_and_notarize_macos_variant "full" "Addivox" || return 1
  sign_and_notarize_macos_variant "demo" "AddivoxDemo"
}

read_plug_version() {
  local config_header="${PROJECT_DIR}/config.h"
  local version

  version="$(sed -E -n 's/^[[:space:]]*#define[[:space:]]+PLUG_VERSION_STR[[:space:]]+"([^"]+)".*$/\1/p' "${config_header}" | head -n 1)"
  if [[ -z "${version}" ]]; then
    echo "Could not read PLUG_VERSION_STR from ${config_header}" >&2
    exit 1
  fi

  PLUG_VERSION="${version}"
}

copy_bundle() {
  local source_path="$1"
  local relative_path="$2"
  local destination_path="${ACTIVE_DIST_ROOT}/${relative_path}"

  mkdir -p "$(dirname "${destination_path}")"
  rm -rf "${destination_path}"
  cp -R "${source_path}" "${destination_path}"
  record_copied_artifact "${destination_path}"
}

copy_named_artifact_from_products_as() {
  local platform_label="$1"
  local products_dir="$2"
  local source_name="$3"
  local destination_name="$4"

  [[ -d "${products_dir}" ]] || return 0

  local artifact_path="${products_dir}/${source_name}"
  if [[ -e "${artifact_path}" ]]; then
    copy_bundle "${artifact_path}" "${platform_label}/${destination_name}"
  else
    record_fail "Copy ${platform_label}/${destination_name} (${artifact_path} not found)"
  fi
}

copy_file() {
  local source_path="$1"
  local relative_path="$2"
  local destination_path="${ACTIVE_DIST_ROOT}/${relative_path}"

  mkdir -p "$(dirname "${destination_path}")"
  rm -f "${destination_path}"
  cp "${source_path}" "${destination_path}"
  record_copied_artifact "${destination_path}"
}

record_copied_artifact() {
  local artifact="$1"

  if [[ "${#COPIED_ARTIFACTS[@]}" -gt 0 ]]; then
    for existing in "${COPIED_ARTIFACTS[@]}"; do
      [[ "${existing}" == "${artifact}" ]] && return 0
    done
  fi

  COPIED_ARTIFACTS+=("${artifact}")
}

record_packaged_artifact() {
  local artifact="$1"

  if [[ "${#PACKAGED_ARTIFACTS[@]}" -gt 0 ]]; then
    for existing in "${PACKAGED_ARTIFACTS[@]}"; do
      [[ "${existing}" == "${artifact}" ]] && return 0
    done
  fi

  PACKAGED_ARTIFACTS+=("${artifact}")
}

copy_packaged_readme() {
  local destination_path="$1"

  sed -E 's/\[([^][]+)\]\([^)]+\)/\1/g' "${MACOS_INSTALLATION_DOC}" > "${destination_path}"
}

copy_named_artifacts_from_products() {
  local platform_label="$1"
  local products_dir="$2"
  shift 2

  [[ -d "${products_dir}" ]] || return 0

  local artifact_name
  for artifact_name in "$@"; do
    local artifact_path="${products_dir}/${artifact_name}"
    if [[ -e "${artifact_path}" ]]; then
      copy_bundle "${artifact_path}" "${platform_label}/${artifact_name}"
    else
      record_fail "Copy ${platform_label}/${artifact_name} (${artifact_path} not found)"
    fi
  done
}

normalize_embedded_macos_auv3() {
  local app_path="${ACTIVE_DIST_ROOT}/macos/${BUILD_BINARY_NAME}.app"
  local plugins_dir="${app_path}/Contents/PlugIns"
  local source_appex="${plugins_dir}/Addivox.appex"
  local destination_appex="${plugins_dir}/${BUILD_BINARY_NAME}.appex"
  local source_executable="${destination_appex}/Contents/MacOS/Addivox"
  local destination_executable="${destination_appex}/Contents/MacOS/${BUILD_BINARY_NAME}"

  if [[ ! -d "${source_appex}" && ! -d "${destination_appex}" ]]; then
    record_fail "Normalize embedded macOS AUv3 (${source_appex} not found)"
    return 0
  fi

  if [[ -d "${source_appex}" && "${source_appex}" != "${destination_appex}" ]]; then
    rm -rf "${destination_appex}"
    mv "${source_appex}" "${destination_appex}"
  fi

  if [[ -f "${source_executable}" && "${source_executable}" != "${destination_executable}" ]]; then
    rm -f "${destination_executable}"
    mv "${source_executable}" "${destination_executable}"
  fi

  if [[ ! -f "${destination_executable}" ]]; then
    record_fail "Normalize embedded macOS AUv3 (${destination_executable} not found)"
  fi
}

copy_macos_scheme_artifacts() {
  local scheme="$1"
  local products_dir="$2"

  case "${scheme}" in
    "macOS-APP")
      copy_named_artifacts_from_products "macos" "${products_dir}" "${BUILD_BINARY_NAME}.app"
      ;;
    "macOS-APP with AUv3")
      copy_named_artifacts_from_products "macos" "${products_dir}" "${BUILD_BINARY_NAME}.app"
      normalize_embedded_macos_auv3
      ;;
    "macOS-AUv2")
      copy_named_artifacts_from_products "macos" "${products_dir}" "${BUILD_BINARY_NAME}.component"
      ;;
    "macOS-VST2")
      copy_named_artifacts_from_products "macos" "${products_dir}" "${BUILD_BINARY_NAME}.vst"
      ;;
    "macOS-VST3")
      copy_named_artifacts_from_products "macos" "${products_dir}" "${BUILD_BINARY_NAME}.vst3"
      ;;
    "macOS-CLAP")
      copy_named_artifacts_from_products "macos" "${products_dir}" "${BUILD_BINARY_NAME}.clap"
      ;;
  esac
}

copy_ios_scheme_artifacts() {
  local platform_label="$1"
  local scheme="$2"
  local products_dir="$3"

  case "${scheme}" in
    "iOS-APP with AUv3")
      copy_named_artifacts_from_products "${platform_label}" "${products_dir}" "${BUILD_BINARY_NAME}.app" "AUv3Framework.framework"
      copy_named_artifact_from_products_as "${platform_label}" "${products_dir}" "AddivoxAppExtension.appex" "${BUILD_BINARY_NAME}AppExtension.appex"
      ;;
    "iOS-AUv3")
      copy_named_artifact_from_products_as "${platform_label}" "${products_dir}" "AddivoxAppExtension.appex" "${BUILD_BINARY_NAME}AppExtension.appex"
      ;;
    "iOS-AUv3Framework")
      copy_named_artifacts_from_products "${platform_label}" "${products_dir}" "AUv3Framework.framework"
      ;;
  esac
}

install_plugin_bundle() {
  local bundle_path="$1"
  local bundle_name
  bundle_name="$(basename "${bundle_path}")"

  case "${bundle_name}" in
    *.component)
      install_bundle_to "${bundle_path}" "${HOME}/Library/Audio/Plug-Ins/Components/${bundle_name}"
      ;;
    *.vst)
      install_bundle_to "${bundle_path}" "${HOME}/Library/Audio/Plug-Ins/VST/${bundle_name}"
      ;;
    *.vst3)
      install_bundle_to "${bundle_path}" "${HOME}/Library/Audio/Plug-Ins/VST3/${bundle_name}"
      ;;
    *.clap)
      install_bundle_to "${bundle_path}" "${HOME}/Library/Audio/Plug-Ins/CLAP/${bundle_name}"
      ;;
  esac
}

install_bundle_to() {
  local source_path="$1"
  local destination_path="$2"

  mkdir -p "$(dirname "${destination_path}")"
  rm -rf "${destination_path}"
  cp -R "${source_path}" "${destination_path}"
  echo "Installed ${destination_path}"
}

install_plugins() {
  log "Installing macOS plugin bundles for local testing"

  while IFS= read -r -d '' bundle; do
    install_plugin_bundle "${bundle}"
  done < <(find "${DIST_ROOT}/full/macos" "${DIST_ROOT}/demo/macos" -type d \( \
      -name "*.component" -o \
      -name "*.vst" -o \
      -name "*.vst3" -o \
      -name "*.clap" \
    \) -prune -print0 2>/dev/null)
}

xcode_build() {
  local project_path="$1"
  local scheme="$2"
  local sdk="$3"
  local destination="$4"
  local derived_data="$5"
  local log_file="$6"
  local name="$7"

  run_step "${name}" "${log_file}" \
    env "ADDIVOX_DEMO=${ADDIVOX_DEMO_VALUE}" \
      xcodebuild \
      -project "${project_path}" \
      -scheme "${scheme}" \
      -configuration "${CONFIGURATION}" \
      -sdk "${sdk}" \
      -destination "${destination}" \
      -derivedDataPath "${derived_data}" \
      SYMROOT="${derived_data}/Products" \
      OBJROOT="${derived_data}/Intermediates" \
      DSTROOT="${derived_data}/DSTROOT" \
      ADDIVOX_DEMO="${ADDIVOX_DEMO_VALUE}" \
      BINARY_NAME="${BUILD_BINARY_NAME}" \
      ADDIVOX_DEVELOPMENT_TEAM="${ADDIVOX_DEVELOPMENT_TEAM}" \
      DEVELOPMENT_TEAM="${ADDIVOX_DEVELOPMENT_TEAM}" \
      GCC_PREPROCESSOR_DEFINITIONS="\$(inherited) ADDIVOX_DEMO=${ADDIVOX_DEMO_VALUE}" \
      DEPLOYMENT_LOCATION=NO \
      SKIP_INSTALL=NO \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGNING_REQUIRED=NO \
      build
}

xcode_archive() {
  local project_path="$1"
  local scheme="$2"
  local destination="$3"
  local archive_path="$4"
  local derived_data="$5"
  local log_file="$6"
  local name="$7"

  mkdir -p "$(dirname "${archive_path}")"

  run_step "${name}" "${log_file}" \
    env "ADDIVOX_DEMO=${ADDIVOX_DEMO_VALUE}" \
      xcodebuild \
      -project "${project_path}" \
      -scheme "${scheme}" \
      -configuration "${CONFIGURATION}" \
      -destination "${destination}" \
      -derivedDataPath "${derived_data}" \
      -archivePath "${archive_path}" \
      ADDIVOX_DEMO="${ADDIVOX_DEMO_VALUE}" \
      BINARY_NAME="${BUILD_BINARY_NAME}" \
      ADDIVOX_DEVELOPMENT_TEAM="${ADDIVOX_DEVELOPMENT_TEAM}" \
      DEVELOPMENT_TEAM="${ADDIVOX_DEVELOPMENT_TEAM}" \
      GCC_PREPROCESSOR_DEFINITIONS="\$(inherited) ADDIVOX_DEMO=${ADDIVOX_DEMO_VALUE}" \
      SKIP_INSTALL=NO \
      DEPLOYMENT_POSTPROCESSING=NO \
      STRIP_INSTALLED_PRODUCT=NO \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGNING_REQUIRED=NO \
      archive
}

build_macos() {
  local derived_data="${XCODE_DERIVED_ROOT}/${BUILD_VARIANT}/macos"

  for scheme in "${MAC_SCHEMES[@]}"; do
    local safe_scheme="${scheme// /_}"
    if xcode_build \
      "${MAC_PROJECT}" \
      "${scheme}" \
      "macosx" \
      "generic/platform=macOS" \
      "${derived_data}" \
      "${LOG_ROOT}/${BUILD_VARIANT}-macos-${safe_scheme}.log" \
      "${BUILD_VARIANT} macOS ${scheme}"; then
      copy_macos_scheme_artifacts "${scheme}" "${derived_data}/Products/${CONFIGURATION}"
    fi
  done
}

build_ios_devices() {
  local derived_data="${XCODE_DERIVED_ROOT}/${BUILD_VARIANT}/ios-device"

  for scheme in "${IOS_SCHEMES[@]}"; do
    local safe_scheme="${scheme// /_}"
    if xcode_build \
      "${IOS_PROJECT}" \
      "${scheme}" \
      "iphoneos" \
      "generic/platform=iOS" \
      "${derived_data}" \
      "${LOG_ROOT}/${BUILD_VARIANT}-ios-device-${safe_scheme}.log" \
      "${BUILD_VARIANT} iOS device ${scheme}"; then
      copy_ios_scheme_artifacts "ios-device" "${scheme}" "${derived_data}/Products/${CONFIGURATION}-iphoneos"
    fi
  done
}

build_ios_simulators() {
  local derived_data="${XCODE_DERIVED_ROOT}/${BUILD_VARIANT}/ios-simulator"

  for scheme in "${IOS_SCHEMES[@]}"; do
    local safe_scheme="${scheme// /_}"
    if xcode_build \
      "${IOS_PROJECT}" \
      "${scheme}" \
      "iphonesimulator" \
      "generic/platform=iOS Simulator" \
      "${derived_data}" \
      "${LOG_ROOT}/${BUILD_VARIANT}-ios-simulator-${safe_scheme}.log" \
      "${BUILD_VARIANT} iOS simulator ${scheme}"; then
      copy_ios_scheme_artifacts "ios-simulator" "${scheme}" "${derived_data}/Products/${CONFIGURATION}-iphonesimulator"
    fi
  done
}

build_archives() {
  local mac_derived="${XCODE_DERIVED_ROOT}/${BUILD_VARIANT}/macos-archives"
  local ios_derived="${XCODE_DERIVED_ROOT}/${BUILD_VARIANT}/ios-archives"

  for scheme in "${ARCHIVE_SCHEMES_MAC[@]}"; do
    local safe_scheme="${scheme// /_}"
    local archive_path="${ARCHIVE_ROOT}/${BUILD_VARIANT}/macos/${scheme}.xcarchive"

    if xcode_archive \
      "${MAC_PROJECT}" \
      "${scheme}" \
      "generic/platform=macOS" \
      "${archive_path}" \
      "${mac_derived}" \
      "${LOG_ROOT}/${BUILD_VARIANT}-archive-macos-${safe_scheme}.log" \
      "${BUILD_VARIANT} archive macOS ${scheme}"; then
      copy_bundle "${archive_path}" "archives/macos/${scheme}.xcarchive"
    fi
  done

  for scheme in "${ARCHIVE_SCHEMES_IOS[@]}"; do
    local safe_scheme="${scheme// /_}"
    local archive_path="${ARCHIVE_ROOT}/${BUILD_VARIANT}/ios/${scheme}.xcarchive"

    if xcode_archive \
      "${IOS_PROJECT}" \
      "${scheme}" \
      "generic/platform=iOS" \
      "${archive_path}" \
      "${ios_derived}" \
      "${LOG_ROOT}/${BUILD_VARIANT}-archive-ios-${safe_scheme}.log" \
      "${BUILD_VARIANT} archive iOS ${scheme}"; then
      copy_bundle "${archive_path}" "archives/ios/${scheme}.xcarchive"
    fi
  done
}

build_cli() {
  local log_file="${LOG_ROOT}/${BUILD_VARIANT}-cli-cmake.log"
  local cmake_build_dir="${CMAKE_BUILD_DIR}-${BUILD_VARIANT}"

  run_step "Configure CLI with CMake" "${log_file}" \
    cmake \
      -S "${PROJECT_DIR}" \
      -B "${cmake_build_dir}" \
      -DCMAKE_BUILD_TYPE="${CONFIGURATION}" \
      -DADDIVOX_DEMO="$([[ "${ADDIVOX_DEMO_VALUE}" -eq 1 ]] && printf ON || printf OFF)" \
      -DIPLUG2_DIR="${ADDIVOX_REPO_DIR}/iPlug2"

  run_step "Build CLI" "${LOG_ROOT}/${BUILD_VARIANT}-cli-build.log" \
    cmake \
      --build "${cmake_build_dir}" \
      --config "${CONFIGURATION}" \
      --target addivox-cli

  local cli_binary="${cmake_build_dir}/${BUILD_CLI_NAME}"
  if [[ -x "${cli_binary}" ]]; then
    copy_file "${cli_binary}" "cli/${BUILD_CLI_NAME}"
  else
    record_fail "Copy CLI artifact (${cli_binary} not found)"
  fi
}

reset_generated_resource_metadata() {
  log "Resetting generated resource metadata to full build defaults"
  (
    cd "${PROJECT_DIR}/projects" &&
      TARGET_BUILD_DIR="${WORK_ROOT}/resource-reset" UNLOCALIZED_RESOURCES_FOLDER_PATH="Resources" ADDIVOX_DEMO=0 python3 ../scripts/prepare_resources-mac.py &&
      ADDIVOX_DEMO=0 python3 ../scripts/prepare_resources-ios.py
  )
}

build_variant() {
  BUILD_VARIANT="$1"
  ADDIVOX_DEMO_VALUE="$2"

  if [[ "${ADDIVOX_DEMO_VALUE}" -eq 1 ]]; then
    BUILD_BINARY_NAME="AddivoxDemo"
    BUILD_CLI_NAME="addivox-demo"
  else
    BUILD_BINARY_NAME="Addivox"
    BUILD_CLI_NAME="addivox"
  fi

  ACTIVE_DIST_ROOT="${DIST_ROOT}/${BUILD_VARIANT}"
  log "Building ${BUILD_VARIANT} artifacts"
  build_macos
  build_ios_devices
  build_ios_simulators
  build_archives
  build_cli
}

package_macos_variant() {
  local variant="$1"
  local binary_name="$2"
  local source_dir="${DIST_ROOT}/${variant}/macos"
  local package_name="${binary_name}_v${PLUG_VERSION}_macOS.zip"
  local package_path="${BUILD_ROOT}/${package_name}"
  local staging_dir="${PACKAGE_ROOT}/${binary_name}"
  local artifact_names=(
    "${binary_name}.app"
    "${binary_name}.component"
    "${binary_name}.vst"
    "${binary_name}.vst3"
    "${binary_name}.clap"
  )
  local package_entries=("README.md" "${artifact_names[@]}")

  log "Packaging ${package_name}"
  mkdir -p "${PACKAGE_ROOT}"
  rm -rf "${staging_dir}" "${package_path}"
  mkdir -p "${staging_dir}"

  local missing=0
  if [[ -f "${MACOS_INSTALLATION_DOC}" ]]; then
    if ! copy_packaged_readme "${staging_dir}/README.md"; then
      record_fail "Package ${package_name} (could not create README.md from ${MACOS_INSTALLATION_DOC})"
      missing=1
    fi
  else
    record_fail "Package ${package_name} (${MACOS_INSTALLATION_DOC} not found)"
    missing=1
  fi

  local artifact_name
  for artifact_name in "${artifact_names[@]}"; do
    local artifact_path="${source_dir}/${artifact_name}"
    if [[ -e "${artifact_path}" ]]; then
      cp -R "${artifact_path}" "${staging_dir}/${artifact_name}"
    else
      record_fail "Package ${package_name} (${artifact_path} not found)"
      missing=1
    fi
  done

  if [[ "${missing}" -ne 0 ]]; then
    return 0
  fi

  (
    cd "${staging_dir}" &&
      zip -qry --symlinks "${package_path}" "${package_entries[@]}"
  )

  if [[ -f "${package_path}" ]]; then
    record_packaged_artifact "${package_path}"
    record_ok "Package ${package_name}"
  else
    record_fail "Package ${package_name} (${package_path} not created)"
  fi
}

package_macos_distributables() {
  package_macos_variant "full" "Addivox"
  package_macos_variant "demo" "AddivoxDemo"
}

print_summary() {
  printf '\n'
  printf '============================================================\n'
  printf 'Addivox build summary\n'
  printf '============================================================\n'
  printf 'Build root: %s\n' "${WORK_ROOT}"
  printf 'Dist root:  %s\n' "${DIST_ROOT}"
  printf 'Logs:       %s\n' "${LOG_ROOT}"

  printf '\nSuccessful steps: %d\n' "${#OK_STEPS[@]}"
  if [[ "${#OK_STEPS[@]}" -gt 0 ]]; then
    for item in "${OK_STEPS[@]}"; do
      printf '  [OK] %s\n' "${item}"
    done
  fi

  printf '\nFailed steps: %d\n' "${#FAILED_STEPS[@]}"
  if [[ "${#FAILED_STEPS[@]}" -gt 0 ]]; then
    for item in "${FAILED_STEPS[@]}"; do
      printf '  [FAIL] %s\n' "${item}"
    done
  fi

  printf '\nCopied artifacts: %d\n' "${#COPIED_ARTIFACTS[@]}"
  if [[ "${#COPIED_ARTIFACTS[@]}" -gt 0 ]]; then
    for item in "${COPIED_ARTIFACTS[@]}"; do
      printf '  %s\n' "${item}"
    done
  fi

  printf '\nPackaged artifacts: %d\n' "${#PACKAGED_ARTIFACTS[@]}"
  if [[ "${#PACKAGED_ARTIFACTS[@]}" -gt 0 ]]; then
    for item in "${PACKAGED_ARTIFACTS[@]}"; do
      printf '  %s\n' "${item}"
    done
  fi

  if [[ "${INSTALL_PLUGINS}" -eq 1 ]]; then
    printf '\nPlugin install requested: yes\n'
  else
    printf '\nPlugin install requested: no. Use --install to copy macOS plugins to ~/Library/Audio/Plug-Ins for local testing.\n'
  fi

  if [[ "${SIGN_AND_NOTARIZE}" -eq 1 ]]; then
    printf '\nSigning/export status: macOS app, AU/VST/CLAP bundles were Developer ID signed, notarized, and stapled where supported.\n'
    printf 'Signing identity: %s\n' "${DEVELOPER_ID_APPLICATION}"
    printf 'Notary profile:   %s\n' "${NOTARY_PROFILE}"
  else
    printf '\nSigning/export status: unsigned build artifacts only. Use --sign_and_notarize before customer distribution.\n'
  fi
}

main() {
  require_tool xcodebuild
  require_tool cmake
  require_tool zip
  read_plug_version

  if [[ "${CLEAN}" -eq 1 ]]; then
    rm -rf "${BUILD_ROOT}"
  fi

  rm -rf "${DIST_ROOT}" "${XCODE_DERIVED_ROOT}" "${ARCHIVE_ROOT}" "${PACKAGE_ROOT}" "${NOTARY_ROOT}"
  rm -f "${BUILD_ROOT}"/Addivox_v*_macOS.zip "${BUILD_ROOT}"/AddivoxDemo_v*_macOS.zip
  mkdir -p "${DIST_ROOT}" "${LOG_ROOT}" "${ARCHIVE_ROOT}" "${PACKAGE_ROOT}"

  build_variant "full" 0
  build_variant "demo" 1
  reset_generated_resource_metadata

  if [[ "${SIGN_AND_NOTARIZE}" -eq 1 ]]; then
    if ! sign_and_notarize_macos_distributables; then
      print_summary
      exit 1
    fi
  fi

  package_macos_distributables

  if [[ "${INSTALL_PLUGINS}" -eq 1 ]]; then
    install_plugins
  fi

  print_summary

  if [[ "${#FAILED_STEPS[@]}" -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
