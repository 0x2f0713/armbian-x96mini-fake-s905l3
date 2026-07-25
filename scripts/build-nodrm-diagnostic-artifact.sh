#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

DISABLE_MESON_DRM=true \
BUILD_MODULES="${BUILD_MODULES:-false}" \
LOCALVERSION="${LOCALVERSION:--x96nodrm-gnu15}" \
ARTIFACT_ROOT="${ARTIFACT_ROOT:-${ROOT}/artifacts/hdmi-nodrm}" \
"${ROOT}/scripts/build-hdmi-test-artifact.sh"
