#!/usr/bin/env bash
# ==============================================================================
# Script: sign_apk.sh
# Purpose: Secure APK signing using GitHub Secrets and apksigner
# ==============================================================================
set -euo pipefail

echo "=================================================="
echo "▶ Phase 4: Secure APK Signing"
echo "=================================================="

WORK_DIR="${WORK_DIR:-$(pwd)/build_workspace}"
ALIGNED_APK="${WORK_DIR}/package_aligned.apk"
FINAL_SIGNED_APK="${WORK_DIR}/GC5_V4.4_Modded_Signed.apk"

ALLOW_FALLBACK_DEBUG_SIGNING="${ALLOW_FALLBACK_DEBUG_SIGNING:-false}"
KEYSTORE_BASE64="${KEYSTORE_BASE64:-}"
KEYSTORE_PASSWORD="${KEYSTORE_PASSWORD:-}"
KEY_ALIAS="${KEY_ALIAS:-}"
KEY_PASSWORD="${KEY_PASSWORD:-}"

# Ensure apksigner is installed
if ! command -v apksigner &> /dev/null; then
  echo "❌ ERROR: 'apksigner' tool is not found in PATH." >&2
  exit 1
fi

if [[ ! -f "${ALIGNED_APK}" ]]; then
  echo "❌ ERROR: Aligned APK not found at ${ALIGNED_APK}" >&2
  exit 1
fi

TEMP_KEYSTORE="${WORK_DIR}/temp_signing.keystore"
cleanup_keystore() {
  if [[ -f "${TEMP_KEYSTORE}" ]]; then
    rm -f "${TEMP_KEYSTORE}"
  fi
}
trap cleanup_keystore EXIT

IS_DEBUG_KEY=false

# 1. Determine signing credentials
if [[ -n "${KEYSTORE_BASE64}" && -n "${KEYSTORE_PASSWORD}" && -n "${KEY_ALIAS}" && -n "${KEY_PASSWORD}" ]]; then
  echo "🔐 Using production signing credentials from GitHub Secrets..."
  echo "${KEYSTORE_BASE64}" | base64 -d > "${TEMP_KEYSTORE}"
  SIGN_KS="${TEMP_KEYSTORE}"
  SIGN_KS_PASS="${KEYSTORE_PASSWORD}"
  SIGN_KEY_ALIAS="${KEY_ALIAS}"
  SIGN_KEY_PASS="${KEY_PASSWORD}"
else
  if [[ "${ALLOW_FALLBACK_DEBUG_SIGNING}" == "true" ]]; then
    echo "⚠️ ==============================================================="
    echo "⚠️ WARNING: Production signing secrets not detected!"
    echo "⚠️ ALLOW_FALLBACK_DEBUG_SIGNING=true is active."
    echo "⚠️ Generating an ephemeral debug key for testing/preview purposes."
    echo "⚠️ ==============================================================="
    
    if ! command -v keytool &> /dev/null; then
      echo "❌ ERROR: 'keytool' is required to generate a debug keystore." >&2
      exit 1
    fi
    
    SIGN_KS_PASS="android"
    SIGN_KEY_ALIAS="androiddebugkey"
    SIGN_KEY_PASS="android"
    
    keytool -genkeypair -v \
      -keystore "${TEMP_KEYSTORE}" \
      -alias "${SIGN_KEY_ALIAS}" \
      -keyalg RSA \
      -keysize 2048 \
      -validity 10000 \
      -storepass "${SIGN_KS_PASS}" \
      -keypass "${SIGN_KEY_PASS}" \
      -dname "CN=Android Debug,O=Android,C=US" > /dev/null 2>&1
      
    SIGN_KS="${TEMP_KEYSTORE}"
    IS_DEBUG_KEY=true
  else
    echo "❌ ERROR: Missing required APK signing secrets!" >&2
    echo "" >&2
    echo "Please configure the following GitHub Secrets in your repository:" >&2
    echo "  - KEYSTORE_BASE64    : Base64-encoded JKS or PKCS12 keystore file" >&2
    echo "  - KEYSTORE_PASSWORD  : Password to unlock the keystore" >&2
    echo "  - KEY_ALIAS          : Alias name of your signing key" >&2
    echo "  - KEY_PASSWORD       : Password for your signing key" >&2
    echo "" >&2
    echo "Or, if you only want to test without a custom key, set the input:" >&2
    echo "  allow_fallback_debug_signing: true" >&2
    exit 1
  fi
fi

# 2. Sign APK with apksigner enforcing v1, v2, and v3 schemes
echo "✍️ Signing APK with apksigner (v1, v2, v3 schemes enabled)..."

apksigner sign \
  --ks "${SIGN_KS}" \
  --ks-pass "pass:${SIGN_KS_PASS}" \
  --ks-key-alias "${SIGN_KEY_ALIAS}" \
  --key-pass "pass:${SIGN_KEY_PASS}" \
  --v1-signing-enabled true \
  --v2-signing-enabled true \
  --v3-signing-enabled true \
  --out "${FINAL_SIGNED_APK}" \
  "${ALIGNED_APK}"

if [[ ! -f "${FINAL_SIGNED_APK}" ]]; then
  echo "❌ ERROR: Signing step did not produce ${FINAL_SIGNED_APK}" >&2
  exit 1
fi

echo "✓ Signing completed."

# 3. Export variables
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "signed_apk_path=${FINAL_SIGNED_APK}" >> "${GITHUB_OUTPUT}"
  echo "is_debug_signed=${IS_DEBUG_KEY}" >> "${GITHUB_OUTPUT}"
fi

echo "=================================================="
echo "✓ Secure signing phase completed."
echo "=================================================="
