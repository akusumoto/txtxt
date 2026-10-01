#!/usr/bin/env bash
# Builds a release binary and packages it as a real macOS .app bundle, so
# double-clicking it launches the GUI directly instead of via Terminal.
set -euo pipefail

cd "$(dirname "$0")/.."

cargo build --release

APP_NAME="txtxt"
BUNDLE_DIR="target/release/bundle/macos/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}"

cp "target/release/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
cp "packaging/Info.plist" "${CONTENTS_DIR}/Info.plist"

# Also place the bundle at the repo root so it's the obvious thing to
# double-click in Finder, instead of the bare `target/release/txtxt`
# executable (which Finder runs inside Terminal.app, not as a GUI app).
rm -rf "${APP_NAME}.app"
cp -R "${BUNDLE_DIR}" "${APP_NAME}.app"

echo "Bundled ${BUNDLE_DIR}"
echo "Also copied to ./${APP_NAME}.app — double-click this one, not target/release/${APP_NAME}"
