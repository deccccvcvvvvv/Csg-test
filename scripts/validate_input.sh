#!/usr/bin/env bash
# ==============================================================================
# Script: validate_input.sh
# Purpose: Validate user inputs, source URLs/paths, and release parameters
# ==============================================================================
set -euo pipefail

echo "=================================================="
echo "▶ Phase 1: Validating Workflow Inputs"
echo "=================================================="

INPUT_MODE="${INPUT_MODE:-complete_apk}"
APK_SOURCE="${APK_SOURCE:-}"
PATCH_SOURCE="${PATCH_SOURCE:-}"
EXPECTED_SHA256="${EXPECTED_SHA256:-}"
RELEASE_TAG="${RELEASE_TAG:-}"
RELEASE_TITLE="${RELEASE_TITLE:-}"

echo "Input Mode:           ${INPUT_MODE}"
echo "APK Source:           ${APK_SOURCE}"
echo "Release Tag:          ${RELEASE_TAG}"
echo "Release Title:        ${RELEASE_TITLE}"

# 1. Validate Input Mode
case "${INPUT_MODE}" in
  complete_apk)
    echo "✓ Selected mode: Mode A (Complete Modified APK)"
    ;;
  asset_patch)
    echo "✓ Selected mode: Mode B (Unity Asset Patch onto Base APK)"
    ;;
  *)
    echo "❌ ERROR: Unsupported INPUT_MODE '${INPUT_MODE}'." >&2
    echo "   Supported modes are: 'complete_apk', 'asset_patch'." >&2
    exit 1
    ;;
esac

# 2. Validate APK Source
if [[ -z "${APK_SOURCE}" ]]; then
  echo "❌ ERROR: APK_SOURCE is empty. Provide a direct download URL or workspace file path." >&2
  exit 1
fi

if [[ "${APK_SOURCE}" =~ ^https?:// ]]; then
  echo "✓ APK Source is a remote URL."
  # Check if URL is accessible with HTTP HEAD or GET range
  HTTP_STATUS=$(curl -sIL -o /dev/null -w "%{http_code}" --connect-timeout 15 "${APK_SOURCE}" || echo "000")
  if [[ "${HTTP_STATUS}" =~ ^(200|301|302|307|308)$ ]]; then
    echo "✓ Remote URL is reachable (HTTP ${HTTP_STATUS})."
  else
    echo "⚠️ WARNING: Remote URL returned HTTP ${HTTP_STATUS}. Download will be attempted during preparation."
  fi
else
  echo "✓ APK Source is a local filesystem path: ${APK_SOURCE}"
  if [[ ! -f "${APK_SOURCE}" ]]; then
    echo "❌ ERROR: Specified local file does not exist: ${APK_SOURCE}" >&2
    exit 1
  fi
fi

# 3. Mode B Specific Validations
if [[ "${INPUT_MODE}" == "asset_patch" ]]; then
  if [[ -z "${PATCH_SOURCE}" ]]; then
    echo "❌ ERROR: Mode B requires PATCH_SOURCE (path or URL to modified assets archive)." >&2
    exit 1
  fi
  echo "✓ Patch source specified: ${PATCH_SOURCE}"
fi

# 4. Validate Release Tag
if [[ -z "${RELEASE_TAG}" ]]; then
  # Generate default release tag using current date and short run ID
  TIMESTAMP=$(date -u +"%Y%m%d-%H%M")
  RELEASE_TAG="v4.4-mod-${TIMESTAMP}"
  echo "ℹ️ Release tag not provided. Auto-generated tag: ${RELEASE_TAG}"
fi

# Sanitize release tag (alphanumeric, dot, dash, underscore only)
if [[ ! "${RELEASE_TAG}" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "❌ ERROR: Invalid release tag '${RELEASE_TAG}'. Use only letters, numbers, dots, dashes, and underscores." >&2
  exit 1
fi

# 5. Validate Release Title
if [[ -z "${RELEASE_TITLE}" ]]; then
  RELEASE_TITLE="GC5 v4.4 Mobile Mod (${RELEASE_TAG})"
  echo "ℹ️ Auto-generated release title: ${RELEASE_TITLE}"
fi

# 6. Check SHA256 checksum format if provided
if [[ -n "${EXPECTED_SHA256}" ]]; then
  if [[ ! "${EXPECTED_SHA256}" =~ ^[a-fA-F0-9]{64}$ ]]; then
    echo "❌ ERROR: EXPECTED_SHA256 does not match valid 64-character SHA256 hex string." >&2
    exit 1
  fi
  echo "✓ SHA256 checksum format valid."
fi

# 7. Export variables for GitHub Actions step outputs if running in Actions
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "validated_input_mode=${INPUT_MODE}" >> "${GITHUB_OUTPUT}"
  echo "validated_release_tag=${RELEASE_TAG}" >> "${GITHUB_OUTPUT}"
  echo "validated_release_title=${RELEASE_TITLE}" >> "${GITHUB_OUTPUT}"
fi

echo "=================================================="
echo "✓ Input validation completed successfully."
echo "=================================================="
