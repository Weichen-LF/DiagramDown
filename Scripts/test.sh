#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
derived_data_path="${DIAGRAMDOWN_DERIVED_DATA_PATH:-/tmp/DiagramDownTestDerivedData}"
xcodebuild_overrides=(
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
)

cd "$repository_root"

for script in Scripts/*.sh; do
  zsh -n "$script"
done

xcodebuild \
  -project Mark.xcodeproj \
  -scheme Mark \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data_path" \
  "${xcodebuild_overrides[@]}" \
  -skip-testing:MarkTests/NativePreviewBenchmarkTests \
  test
