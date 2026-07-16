#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./Scripts/release.sh [options]

Options:
  --notary-profile NAME  Submit with credentials stored by notarytool, then staple.
  --output DIRECTORY     Write release artifacts under DIRECTORY (default: artifacts).
  --skip-tests           Skip the automated test suite.
  --allow-dirty          Allow a release build from a dirty Git worktree.
  -h, --help             Show this help.

The script never publishes a release. Without --notary-profile it stops after
Developer ID export, validation, and ZIP creation.
EOF
}

fail() {
  print -u2 -- "Release failed: $1"
  exit 1
}

repository_root="${0:A:h:h}"
project_path="$repository_root/Mark.xcodeproj"
scheme="Mark"
export_options="$repository_root/Config/ExportOptions-DeveloperID.plist"
output_root="$repository_root/artifacts"
notary_profile=""
skip_tests=false
allow_dirty=false

while (( $# > 0 )); do
  case "$1" in
    --notary-profile)
      (( $# >= 2 )) || fail "--notary-profile requires a profile name."
      notary_profile="$2"
      shift
      ;;
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

[[ "$(uname -m)" == "arm64" ]] || fail "This release currently requires an Apple Silicon Mac."
[[ -f "$export_options" ]] || fail "Missing Developer ID export options."

if [[ "$allow_dirty" != true && -n "$(git status --porcelain)" ]]; then
  fail "The Git worktree is not clean. Commit or stash changes, or pass --allow-dirty intentionally."
fi

signing_identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
[[ "$signing_identities" == *'"Developer ID Application:'* ]] || fail "No Developer ID Application identity is available in the keychain."

if [[ "$skip_tests" != true ]]; then
  "$repository_root/Scripts/test.sh"
fi

build_settings="$(xcodebuild -project "$project_path" -scheme "$scheme" -configuration Release -showBuildSettings)"
marketing_version="$(print -r -- "$build_settings" | awk '/ MARKETING_VERSION = / { print $3; exit }')"
project_build_number="$(print -r -- "$build_settings" | awk '/ CURRENT_PROJECT_VERSION = / { print $3; exit }')"
build_number="${BUILD_NUMBER:-$project_build_number}"
[[ -n "$marketing_version" ]] || fail "Could not determine MARKETING_VERSION."
[[ -n "$build_number" ]] || fail "Could not determine CURRENT_PROJECT_VERSION."

mkdir -p "$output_root"
output_root="${output_root:A}"
timestamp="$(date '+%Y%m%d-%H%M%S')"
release_directory="$output_root/DiagramDown-$marketing_version-$build_number-$timestamp"
archive_path="$release_directory/DiagramDown.xcarchive"
export_path="$release_directory/export"
app_path="$export_path/DiagramDown.app"
zip_path="$release_directory/DiagramDown-$marketing_version-$build_number-arm64.zip"
mkdir -p "$release_directory"

print -- "Archiving DiagramDown $marketing_version ($build_number)..."
xcodebuild \
  -project "$project_path" \
  -scheme "$scheme" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CURRENT_PROJECT_VERSION="$build_number" \
  archive

print -- "Exporting with Developer ID..."
xcodebuild \
  -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$export_options"

[[ -d "$app_path" ]] || fail "Export did not produce DiagramDown.app."
"$repository_root/Scripts/validate-release.sh" "$app_path" --distribution

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

if [[ -n "$notary_profile" ]]; then
  print -- "Submitting to Apple's notary service..."
  xcrun notarytool submit "$zip_path" \
    --keychain-profile "$notary_profile" \
    --wait \
    --timeout 30m

  print -- "Stapling the notarization ticket..."
  xcrun stapler staple "$app_path"
  "$repository_root/Scripts/validate-release.sh" "$app_path" --notarized

  rm -f "$zip_path"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"
fi

print -- "Release artifact: $zip_path"
print -- "Archive: $archive_path"
if [[ -z "$notary_profile" ]]; then
  print -- "Notarization was not requested. Re-run with --notary-profile NAME for a distributable artifact."
else
  print -- "The ZIP contains the stapled, Gatekeeper-validated application. Publishing remains a separate manual step."
fi
