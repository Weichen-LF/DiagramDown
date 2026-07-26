#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
derived_data_path="${TMPDIR:-/tmp}/DiagramDownBenchmarkDerivedData"
metrics_path="/tmp/DiagramDownNativePreviewBenchmarkMetrics.log"

cd "$repository_root"
: > "$metrics_path"

xcodebuild \
  -project Mark.xcodeproj \
  -scheme Mark \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data_path" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  -only-testing:MarkTests/NativePreviewBenchmarkTests \
  test

if [[ -s "$metrics_path" ]]; then
  sort "$metrics_path"
fi

app_path="$derived_data_path/Build/Products/Debug/DiagramDown.app"
if [[ -d "$app_path" ]]; then
  app_size_kib="$(du -sk "$app_path" | awk '{ print $1 }')"
  print -- "BENCHMARK debug-app-size kib=$app_size_kib"
fi
