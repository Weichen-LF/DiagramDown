#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
derived_data_path="${DIAGRAMDOWN_DERIVED_DATA_PATH:-/tmp/DiagramDownTestDerivedData}"
xcodebuild_overrides=()

if [[ "${CI:-false}" == "true" ]]; then
  xcodebuild_overrides+=(
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
  )
fi

cd "$repository_root"

node --check Mark/Resources/Preview/preview.js
node --test Tests/PreviewRuntimeTests.mjs

xcodebuild \
  -project Mark.xcodeproj \
  -scheme Mark \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data_path" \
  "${xcodebuild_overrides[@]}" \
  test
