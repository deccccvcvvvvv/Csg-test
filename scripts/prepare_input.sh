#!/usr/bin/env bash
# ==============================================================================
# Script: prepare_input.sh
# Purpose: Fetch, verify integrity, and inspect structure of input APK/assets
# ==============================================================================
set -euo pipefail

echo "=================================================="
echo "▶ Phase 2: Preparing and Inspecting Input Files"
echo "=================================================="

WORK_DIR="${WORK_DIR:-$(pwd)/build_workspace}"
mkdir -p "${WORK_DIR}"

INPUT_MODE="${INPUT_MODE:-complete_apk}"
APK_SOURCE="${APK_SOURCE:-}"
PATCH_SOURCE="${PATCH_SOURCE:-}"
EXPECTED_SHA256="${EXPECTED_SHA256:-}"

TARGET_APK="${WORK_DIR}/input_target.apk"
TARGET_PATCH_DIR="${WORK_DIR}/patches"

# 1. Fetch APK file
if [[ "${APK_SOURCE}" =~ ^https?:// ]]; then
  echo "📥 Downloading input APK from remote URL..."
  curl -fL --retry 3 --retry-delay 5 -C - --progress-bar -o "${TARGET_APK}" "${APK_SOURCE}"
else
  echo "📋 Copying input APK from local path: ${APK_SOURCE}"
  cp "${APK_SOURCE}" "${TARGET_APK}"
fi

# 2. Check File Exists and Size
if [[ ! -f "${TARGET_APK}" ]]; then
  echo "❌ ERROR: Target APK file was not found at ${TARGET_APK}" >&2
  exit 1
fi

FILE_SIZE_BYTES=$(stat -c%s "${TARGET_APK}" 2>/dev/null || stat -f%z "${TARGET_APK}" 2>/dev/null)
FILE_SIZE_MB=$(( FILE_SIZE_BYTES / 1024 / 1024 ))
echo "✓ Input APK downloaded. File size: ${FILE_SIZE_MB} MB (${FILE_SIZE_BYTES} bytes)"

if (( FILE_SIZE_MB < 300 )); then
  echo "❌ ERROR: APK file size (${FILE_SIZE_MB} MB) is unusually small for GC5 (expected ~648 MB)." >&2
  echo "   Verify that the download was complete and not truncated." >&2
  exit 1
fi

# 3. Check SHA256 if provided
ACTUAL_SHA256=$(sha256sum "${TARGET_APK}" | awk '{print $1}')
echo "ℹ️ SHA256: ${ACTUAL_SHA256}"

if [[ -n "${EXPECTED_SHA256}" ]]; then
  if [[ "${ACTUAL_SHA256,,}" != "${EXPECTED_SHA256,,}" ]]; then
    echo "❌ ERROR: SHA256 checksum mismatch!" >&2
    echo "   Expected: ${EXPECTED_SHA256}" >&2
    echo "   Actual:   ${ACTUAL_SHA256}" >&2
    exit 1
  fi
  echo "✓ SHA256 checksum matches verified value."
fi

# 4. Verify ZIP/APK structure integrity
echo "🔍 Testing archive structure integrity..."
if ! unzip -tq "${TARGET_APK}" > /dev/null; then
  echo "❌ ERROR: The provided file is not a valid or undamaged ZIP/APK archive." >&2
  exit 1
fi
echo "✓ Archive integrity test passed."

# 5. Inspect Internal APK Structure (Unity & Android components)
echo "🔍 Inspecting internal Android and Unity IL2CPP components..."

HAS_MANIFEST=$(unzip -l "${TARGET_APK}" | grep -c "AndroidManifest.xml" || true)
HAS_CLASSES_DEX=$(unzip -l "${TARGET_APK}" | grep -c "classes.dex" || true)
HAS_UNITY_DATA=$(unzip -l "${TARGET_APK}" | grep -c "assets/bin/Data/data.unity3d" || true)
HAS_IL2CPP=$(unzip -l "${TARGET_APK}" | grep -c "libil2cpp.so" || true)

if [[ "${HAS_MANIFEST}" -eq 0 ]]; then
  echo "❌ ERROR: Missing AndroidManifest.xml inside the APK!" >&2
  exit 1
fi

if [[ "${HAS_CLASSES_DEX}" -eq 0 ]]; then
  echo "❌ ERROR: Missing classes.dex inside the APK!" >&2
  exit 1
fi

if [[ "${HAS_UNITY_DATA}" -eq 0 ]]; then
  echo "⚠️ WARNING: 'assets/bin/Data/data.unity3d' not found. Verify this is the expected Unity game structure."
else
  echo "✓ UnityFS asset container found: assets/bin/Data/data.unity3d"
fi

if [[ "${HAS_IL2CPP}" -eq 0 ]]; then
  echo "⚠️ WARNING: 'libil2cpp.so' not found in architecture folders."
else
  echo "✓ Unity IL2CPP engine library found (libil2cpp.so)."
fi

# 6. Mode B: Prepare Patch files
if [[ "${INPUT_MODE}" == "asset_patch" ]]; then
  mkdir -p "${TARGET_PATCH_DIR}"
  PATCH_ARCHIVE="${WORK_DIR}/patch_input.zip"
  
  if [[ "${PATCH_SOURCE}" =~ ^https?:// ]]; then
    echo "📥 Downloading asset patch package..."
    curl -fL --retry 3 --retry-delay 5 -o "${PATCH_ARCHIVE}" "${PATCH_SOURCE}"
  else
    echo "📋 Copying asset patch package from: ${PATCH_SOURCE}"
    cp "${PATCH_SOURCE}" "${PATCH_ARCHIVE}"
  fi
  
  echo "📦 Extracting asset patch archive..."
  unzip -q "${PATCH_ARCHIVE}" -d "${TARGET_PATCH_DIR}"
  echo "✓ Extracted patch files into ${TARGET_PATCH_DIR}:"
  ls -lh "${TARGET_PATCH_DIR}"
fi

# 7. Export outputs
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "target_apk_path=${TARGET_APK}" >> "${GITHUB_OUTPUT}"
  echo "target_patch_dir=${TARGET_PATCH_DIR}" >> "${GITHUB_OUTPUT}"
  echo "apk_sha256=${ACTUAL_SHA256}" >> "${GITHUB_OUTPUT}"
  echo "apk_size_mb=${FILE_SIZE_MB}" >> "${GITHUB_OUTPUT}"
fi

echo "=================================================="
echo "✓ Preparation and structural checks completed."
echo "=================================================="
