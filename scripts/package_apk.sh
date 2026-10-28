#!/usr/bin/env bash
# ==============================================================================
# Script: package_apk.sh
# Purpose: Conditional repackaging, asset integration, and zipalign processing
# ==============================================================================
set -euo pipefail

echo "=================================================="
echo "▶ Phase 3: APK Packaging & Alignment"
echo "=================================================="

WORK_DIR="${WORK_DIR:-$(pwd)/build_workspace}"
INPUT_MODE="${INPUT_MODE:-complete_apk}"
INPUT_APK="${WORK_DIR}/input_target.apk"
TARGET_PATCH_DIR="${WORK_DIR}/patches"
UNALIGNED_APK="${WORK_DIR}/package_unaligned.apk"
ALIGNED_APK="${WORK_DIR}/package_aligned.apk"

# Check prerequisite tools
if ! command -v zipalign &> /dev/null; then
  echo "❌ ERROR: 'zipalign' tool is not installed or not in PATH." >&2
  exit 1
fi

if [[ ! -f "${INPUT_APK}" ]]; then
  echo "❌ ERROR: Input APK not found at ${INPUT_APK}" >&2
  exit 1
fi

cp "${INPUT_APK}" "${UNALIGNED_APK}"

# Strip old signatures from META-INF to avoid conflicting signatures
echo "🧹 Removing legacy/original signatures from META-INF..."
zip -d "${UNALIGNED_APK}" "META-INF/*.SF" "META-INF/*.RSA" "META-INF/*.DSA" "META-INF/*.EC" "META-INF/*.MF" 2>/dev/null || true

# Process according to input mode
if [[ "${INPUT_MODE}" == "complete_apk" ]]; then
  echo "ℹ️ Mode A: Complete APK provided. No internal archive restructuring needed."

elif [[ "${INPUT_MODE}" == "asset_patch" ]]; then
  echo "ℹ️ Mode B: Applying Unity asset patches..."
  
  if [[ ! -d "${TARGET_PATCH_DIR}" ]] || [[ -z "$(ls -A "${TARGET_PATCH_DIR}")" ]]; then
    echo "❌ ERROR: Patch directory '${TARGET_PATCH_DIR}' is empty or does not exist." >&2
    exit 1
  fi

  # Check what files are being patched
  echo "🔍 Analyzing patch payload contents..."
  
  # Case 1: Direct Unity Data replacement (e.g. data.unity3d or boot.config)
  if [[ -f "${TARGET_PATCH_DIR}/data.unity3d" ]]; then
    echo "  → Patching assets/bin/Data/data.unity3d..."
    (cd "${TARGET_PATCH_DIR}" && zip -u -0 "${UNALIGNED_APK}" "assets/bin/Data/data.unity3d" 2>/dev/null || zip -u "${UNALIGNED_APK}" "data.unity3d")
  fi

  # Case 2: Direct folder structure inside patch dir
  if [[ -d "${TARGET_PATCH_DIR}/assets" ]]; then
    echo "  → Updating 'assets/' directory hierarchy into APK..."
    (cd "${TARGET_PATCH_DIR}" && zip -u -r "${UNALIGNED_APK}" assets/)
  fi

  # Case 3: Resources or layouts
  if [[ -d "${TARGET_PATCH_DIR}/res" ]]; then
    echo "  → Updating 'res/' resources..."
    (cd "${TARGET_PATCH_DIR}" && zip -u -r "${UNALIGNED_APK}" res/)
  fi

  # Case 4: Native libraries (.so)
  if [[ -d "${TARGET_PATCH_DIR}/lib" ]]; then
    echo "  → Updating native libraries ('lib/') with uncompressed storage for runtime mmap..."
    (cd "${TARGET_PATCH_DIR}" && zip -u -0 -r "${UNALIGNED_APK}" lib/)
  fi

  echo "✓ Patch payload successfully integrated into APK archive."
fi

# Zipalign the APK
echo "📐 Running zipalign on 4-byte boundary..."
rm -f "${ALIGNED_APK}"
zipalign -v -p 4 "${UNALIGNED_APK}" "${ALIGNED_APK}" > /dev/null

# Verify zipalign verification
if ! zipalign -c 4 "${ALIGNED_APK}"; then
  echo "❌ ERROR: zipalign verification failed on ${ALIGNED_APK}" >&2
  exit 1
fi
echo "✓ zipalign verification passed (4-byte alignment verified)."

# Export output path
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "aligned_apk_path=${ALIGNED_APK}" >> "${GITHUB_OUTPUT}"
fi

echo "=================================================="
echo "✓ APK packaging and alignment completed."
echo "=================================================="
