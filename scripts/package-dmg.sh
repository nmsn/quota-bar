#!/bin/bash
set -e

PRODUCT_NAME="QuotaBar"
MARKETING_VERSION="2.0.2"
SCHEME_NAME="quota-bar"
PROJECT_FILE="quota-bar.xcodeproj"

# 1. Build
echo "==> Building ${PRODUCT_NAME}..."
xcodebuild -project "${PROJECT_FILE}" \
  -scheme "${SCHEME_NAME}" \
  -configuration Release \
  -quiet \
  build

# 2. Locate build output
BUILD_DIR=$(xcodebuild -project "${PROJECT_FILE}" -scheme "${SCHEME_NAME}" -configuration Release -showBuildSettings 2>/dev/null | grep "BUILT_PRODUCTS_DIR = " | head -1 | sed 's/.*= //')
APP_PATH="${BUILD_DIR}/${PRODUCT_NAME}.app"

if [ ! -d "${APP_PATH}" ]; then
  echo "Error: App not found at ${APP_PATH}"
  exit 1
fi

# 3. Create dist directory
mkdir -p dist

# 4. Package DMG with create-dmg
echo "==> Creating DMG..."
create-dmg \
  --volname "${PRODUCT_NAME}" \
  --window-pos 200 200 \
  --window-size 600 400 \
  --hide-extension "${PRODUCT_NAME}.app" \
  --app-drop-link 480 170 \
  --icon-size 100 \
  --icon "${PRODUCT_NAME}.app" 150 170 \
  "dist/${PRODUCT_NAME}-${MARKETING_VERSION}.dmg" \
  "${APP_PATH}"

echo "==> DMG created at dist/${PRODUCT_NAME}-${MARKETING_VERSION}.dmg"