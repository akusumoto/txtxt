#!/usr/bin/env bash
# Builds a release binary and packages it as a real macOS .app bundle, so
# double-clicking it launches the GUI directly instead of via Terminal, and
# so NSDocument can find the document types declared in Info.plist.
set -euo pipefail

cd "$(dirname "$0")/.."

# Some Command Line Tools installs carry stale *.private.swiftinterface
# files from an older SwiftPM, which break every manifest build ("Invalid
# manifest" / undefined `Package.init`). Until they're removed (needs
# sudo), point SwiftPM at a clean copy of its libraries instead.
PM_LIBS="$(dirname "$(dirname "$(xcrun --find swift)")")/lib/swift/pm"
if compgen -G "${PM_LIBS}/*/*.swiftmodule/*.private.swiftinterface" > /dev/null; then
    CLEAN_LIBS=".build/clean-pm-libs"
    rm -rf "${CLEAN_LIBS}"
    mkdir -p .build
    cp -R "${PM_LIBS}" "${CLEAN_LIBS}"
    find "${CLEAN_LIBS}" -name "*.private.swiftinterface" -delete
    export SWIFTPM_CUSTOM_LIBS_DIR="${PWD}/${CLEAN_LIBS}"
fi

swift build -c release

APP_NAME="txtxt"
BUNDLE_DIR=".build/bundle/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"

rm -rf "${BUNDLE_DIR}"
mkdir -p "${CONTENTS_DIR}/MacOS" "${CONTENTS_DIR}/Resources"
cp "$(swift build -c release --show-bin-path)/${APP_NAME}" "${CONTENTS_DIR}/MacOS/${APP_NAME}"
cp "packaging/Info.plist" "${CONTENTS_DIR}/Info.plist"
cp "packaging/AppIcon.icns" "${CONTENTS_DIR}/Resources/AppIcon.icns"
codesign --force --sign - "${BUNDLE_DIR}"

# Also place the bundle at the repo root so it's the obvious thing to
# double-click in Finder.
rm -rf "${APP_NAME}.app"
cp -R "${BUNDLE_DIR}" "${APP_NAME}.app"

echo "Bundled ./${APP_NAME}.app"
