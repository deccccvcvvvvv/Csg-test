#!/usr/bin/env bash
# ==============================================================================
# Script: validate_output.sh
# Purpose: Final APK validation, signature audit, and release metadata generation
# ==============================================================================
set -euo pipefail

echo "=================================================="
echo "▶ Phase 5: Final Output APK Validation & Audit"
echo "=================================================="

WORK_DIR="${WORK_DIR:-$(pwd)/build_workspace}"
SIGNED_APK="${WORK_DIR}/GC5_V4.4_Modded_Signed.apk"
RELEASE_NOTES_FILE="${WORK_DIR}/release_notes.md"

if [[ ! -f "${SIGNED_APK}" ]]; then
  echo "❌ ERROR: Signed APK not found at ${SIGNED_APK}" >&2
  exit 1
fi

# 1. Size Verification
FINAL_SIZE_BYTES=$(stat -c%s "${SIGNED_APK}" 2>/dev/null || stat -f%z "${SIGNED_APK}" 2>/dev/null)
FINAL_SIZE_MB=$(( FINAL_SIZE_BYTES / 1024 / 1024 ))

if (( FINAL_SIZE_BYTES == 0 )); then
  echo "❌ ERROR: Signed APK is empty (0 bytes)!" >&2
  exit 1
fi
echo "✓ Final APK size: ${FINAL_SIZE_MB} MB (${FINAL_SIZE_BYTES} bytes)"

# 2. Signature Verification with apksigner
echo "🔐 Running apksigner cryptographic verification..."
VERIFY_OUTPUT=$(apksigner verify --verbose "${SIGNED_APK}" 2>&1 || true)

echo "${VERIFY_OUTPUT}"

if ! echo "${VERIFY_OUTPUT}" | grep -q "Verifies"; then
  echo "❌ ERROR: apksigner verification failed! The output APK is NOT signed properly." >&2
  exit 1
fi

SIG_V1=$(echo "${VERIFY_OUTPUT}" | grep "Verified using v1 scheme" || echo "false")
SIG_V2=$(echo "${VERIFY_OUTPUT}" | grep "Verified using v2 scheme" || echo "false")
SIG_V3=$(echo "${VERIFY_OUTPUT}" | grep "Verified using v3 scheme" || echo "false")
echo "✓ Signature schemes verified: ${SIG_V1}, ${SIG_V2}, ${SIG_V3}"

# 3. Structural & Component Verification
echo "🔍 Verifying internal archive integrity..."
if ! unzip -tq "${SIGNED_APK}" > /dev/null; then
  echo "❌ ERROR: Output APK failed internal ZIP archive integrity check!" >&2
  exit 1
fi

# Check critical Unity IL2CPP components
if ! unzip -l "${SIGNED_APK}" | grep -q "assets/bin/Data/data.unity3d"; then
  echo "❌ ERROR: Crucial Unity game container 'data.unity3d' is missing from the output APK!" >&2
  exit 1
fi

if ! unzip -l "${SIGNED_APK}" | grep -q "libil2cpp.so"; then
  echo "❌ ERROR: Crucial IL2CPP engine library 'libil2cpp.so' is missing from the output APK!" >&2
  exit 1
fi
echo "✓ Core Unity IL2CPP assets and libraries confirmed intact."

# 4. Extract Package Metadata via aapt/aapt2 if available
PACKAGE_NAME="Unknown"
VERSION_NAME="Unknown"
VERSION_CODE="Unknown"

if command -v aapt2 &> /dev/null; then
  echo "📱 Extracting metadata using aapt2..."
  DUMP_OUTPUT=$(aapt2 dump badging "${SIGNED_APK}" 2>/dev/null || true)
  PACKAGE_NAME=$(echo "${DUMP_OUTPUT}" | grep "package: name=" | sed -E "s/.*name='([^']+)'.*/\1/" || echo "Unknown")
  VERSION_CODE=$(echo "${DUMP_OUTPUT}" | grep "package: name=" | sed -E "s/.*versionCode='([^']+)'.*/\1/" || echo "Unknown")
  VERSION_NAME=$(echo "${DUMP_OUTPUT}" | grep "package: name=" | sed -E "s/.*versionName='([^']+)'.*/\1/" || echo "Unknown")
elif command -v aapt &> /dev/null; then
  echo "📱 Extracting metadata using aapt..."
  DUMP_OUTPUT=$(aapt dump badging "${SIGNED_APK}" 2>/dev/null || true)
  PACKAGE_NAME=$(echo "${DUMP_OUTPUT}" | grep "package: name=" | sed -E "s/.*name='([^']+)'.*/\1/" || echo "Unknown")
  VERSION_CODE=$(echo "${DUMP_OUTPUT}" | grep "package: name=" | sed -E "s/.*versionCode='([^']+)'.*/\1/" || echo "Unknown")
  VERSION_NAME=$(echo "${DUMP_OUTPUT}" | grep "package: name=" | sed -E "s/.*versionName='([^']+)'.*/\1/" || echo "Unknown")
fi

echo "✓ Package Name: ${PACKAGE_NAME}"
echo "✓ Version Name: ${VERSION_NAME}"
echo "✓ Version Code: ${VERSION_CODE}"

# 5. Checksum Generation
FINAL_SHA256=$(sha256sum "${SIGNED_APK}" | awk '{print $1}')
FINAL_MD5=$(md5sum "${SIGNED_APK}" | awk '{print $1}')
echo "✓ SHA-256: ${FINAL_SHA256}"
echo "✓ MD5:     ${FINAL_MD5}"

# 6. Generate Release Notes Content
cat <<EOF > "${RELEASE_NOTES_FILE}"
### 🎮 GC5 v4.4 Mobile Mod - Automated Build Release

This release was packaged, aligned, and signed by the automated GitHub Actions pipeline.

#### 📦 Package Details
- **Package Name:** \`${PACKAGE_NAME}\`
- **Version Name:** \`${VERSION_NAME}\`
- **Version Code:** \`${VERSION_CODE}\`
- **File Size:** \`${FINAL_SIZE_MB} MB\` (${FINAL_SIZE_BYTES} bytes)
- **Unity Version:** \`2021.3.45f1\` (IL2CPP)

#### 🔐 Signature & Cryptographic Verification
- **Verified Status:** ✅ apksigner Verified
- **Signature Schemes:** ${SIG_V1} | ${SIG_V2} | ${SIG_V3}
- **SHA-256 Checksum:** \`${FINAL_SHA256}\`
- **MD5 Checksum:** \`${FINAL_MD5}\`

> [!IMPORTANT]
> **Signature Note:** If this APK was signed with a new or debug keystore, you must completely **uninstall the original Play Store / developer version** before installing this APK on your Android device. Android prevents updating apps whose signing certificates do not match.

> [!NOTE]
> Signature verification proves APK integrity and packaging validity. Device gameplay behavior depends on the compatibility of custom game modifications with the Unity runtime and anti-cheat components.
EOF

# 7. Export outputs
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "final_apk_path=${SIGNED_APK}" >> "${GITHUB_OUTPUT}"
  echo "final_sha256=${FINAL_SHA256}" >> "${GITHUB_OUTPUT}"
  echo "release_notes_path=${RELEASE_NOTES_FILE}" >> "${GITHUB_OUTPUT}"
  echo "package_name=${PACKAGE_NAME}" >> "${GITHUB_OUTPUT}"
fi

echo "=================================================="
echo "✓ Final APK validation passed successfully."
echo "=================================================="
