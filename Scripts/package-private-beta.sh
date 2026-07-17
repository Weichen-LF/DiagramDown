#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./Scripts/package-private-beta.sh [options]

Options:
  --output DIRECTORY  Write private-beta artifacts under DIRECTORY (default: artifacts).
  --skip-tests        Skip the automated test suite.
  --allow-dirty       Allow packaging from a dirty Git worktree.
  -h, --help          Show this help.

This produces an Apple Silicon, ad-hoc signed, unnotarized test build. It never
publishes a release and must not be used as an official public artifact.
EOF
}

fail() {
  print -u2 -- "Private-beta packaging failed: $1"
  exit 1
}

repository_root="${0:A:h:h}"
project_path="$repository_root/Mark.xcodeproj"
scheme="Mark"
output_root="$repository_root/artifacts"
derived_data_path="${DIAGRAMDOWN_BETA_DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/DiagramDownPrivateBetaDerivedData}"
skip_tests=false
allow_dirty=false

while (( $# > 0 )); do
  case "$1" in
    --output)
      (( $# >= 2 )) || fail "--output requires a directory."
      output_root="$2"
      shift
      ;;
    --skip-tests)
      skip_tests=true
      ;;
    --allow-dirty)
      allow_dirty=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "Unknown option: $1"
      ;;
  esac
  shift
done

cd "$repository_root"
derived_data_path="${derived_data_path:A}"

[[ "$(uname -m)" == "arm64" ]] || fail "Private-beta packaging requires an Apple Silicon Mac."

if [[ "$allow_dirty" != true && -n "$(git status --porcelain)" ]]; then
  fail "The Git worktree is not clean. Commit or stash changes, or pass --allow-dirty intentionally."
fi

if [[ "$skip_tests" != true ]]; then
  "$repository_root/Scripts/test.sh"
fi

build_settings="$(xcodebuild \
  -project "$project_path" \
  -scheme "$scheme" \
  -configuration Release \
  -derivedDataPath "$derived_data_path" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  -showBuildSettings)"
marketing_version="$(print -r -- "$build_settings" | awk '/ MARKETING_VERSION = / { print $3; exit }')"
project_build_number="$(print -r -- "$build_settings" | awk '/ CURRENT_PROJECT_VERSION = / { print $3; exit }')"
build_number="${BUILD_NUMBER:-$project_build_number}"
[[ -n "$marketing_version" ]] || fail "Could not determine MARKETING_VERSION."
[[ -n "$build_number" ]] || fail "Could not determine CURRENT_PROJECT_VERSION."

mkdir -p "$output_root"
output_root="${output_root:A}"
timestamp="$(date '+%Y%m%d-%H%M%S')"
release_directory="$output_root/DiagramDown-$marketing_version-$build_number-private-beta-$timestamp"
app_path="$release_directory/DiagramDown.app"
zip_name="DiagramDown-$marketing_version-$build_number-arm64-private-beta.zip"
zip_path="$release_directory/$zip_name"
checksum_path="$zip_path.sha256"
mkdir -p "$release_directory"

print -- "Building DiagramDown $marketing_version ($build_number) for private Apple Silicon testing..."
xcodebuild \
  -project "$project_path" \
  -scheme "$scheme" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_data_path" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CURRENT_PROJECT_VERSION="$build_number" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  build

built_app_path="$derived_data_path/Build/Products/Release/DiagramDown.app"
[[ -d "$built_app_path" ]] || fail "The build did not produce DiagramDown.app."
/usr/bin/ditto "$built_app_path" "$app_path"

"$repository_root/Scripts/validate-release.sh" "$app_path" --adhoc
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

(
  cd "$release_directory"
  /usr/bin/shasum -a 256 "$zip_name" > "$zip_name.sha256"
)

print -- ""
print -- "PRIVATE TEST BUILD ONLY"
print -- "This artifact is ad-hoc signed and not notarized. Gatekeeper may block it on another Mac."
print -- "Do not publish it as an official release."
print -- ""
print -- "Application: $app_path"
print -- "ZIP: $zip_path"
print -- "SHA-256: $checksum_path"
