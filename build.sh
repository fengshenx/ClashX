#!/bin/bash

set -e

RUN=false
CONFIG="debug"

for arg in "$@"; do
  case "$arg" in
    debug|release)
      CONFIG="$arg"
      ;;
    run|--run)
      RUN=true
      ;;
    -h|--help)
      echo "Usage: $0 [debug|release] [run]"
      echo "  debug, release  Build configuration (default: debug)"
      echo "  run             Build and open the app after"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: $0 [debug|release] [run]"
      exit 1
      ;;
  esac
done

# Xcode configurations are title-case (Debug/Release)
CONFIG_TITLE="$(tr '[:lower:]' '[:upper:]' <<< "${CONFIG:0:1}")${CONFIG:1}"

echo "Building ClashX ($CONFIG_TITLE)..."

BUILD_DIR=$(xcodebuild -workspace ClashX.xcworkspace \
  -scheme ClashX \
  -configuration "$CONFIG_TITLE" \
  -showBuildSettings 2>/dev/null | grep " BUILT_PRODUCTS_DIR = " | awk '{print $3}')

xcodebuild -workspace ClashX.xcworkspace \
  -scheme ClashX \
  -configuration "$CONFIG_TITLE" \
  -onlyUsePackageVersionsFromResolvedFile \
  build

APP_PATH="$BUILD_DIR/ClashX.app"

if [[ "$RUN" == true ]]; then
  echo "Opening $APP_PATH ..."
  open "$APP_PATH"
fi
