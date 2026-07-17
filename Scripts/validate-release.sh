#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./Scripts/validate-release.sh APP_PATH [--adhoc | --distribution] [--notarized]

  --adhoc        Require local ad-hoc signatures without a signing team.
  --distribution  Require Developer ID Application signatures.
  --notarized     Also validate the stapled ticket and Gatekeeper assessment.
EOF
}

fail() {
  print -u2 -- "Release validation failed: $1"
  exit 1
}

app_path=""
require_adhoc=false
require_distribution=false
require_notarized=false

while (( $# > 0 )); do
  case "$1" in
    --adhoc)
      require_adhoc=true
      ;;
    --distribution)
      require_distribution=true
      ;;
    --notarized)
      require_notarized=true
      require_distribution=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      usage >&2
      fail "Unknown option: $1"
      ;;
    *)
      [[ -z "$app_path" ]] || fail "Only one application path can be validated."
      app_path="$1"
      ;;
  esac
  shift
done

if [[ "$require_adhoc" == true && "$require_distribution" == true ]]; then
  fail "--adhoc cannot be combined with --distribution or --notarized."
fi

[[ -n "$app_path" ]] || {
  usage >&2
  exit 2
}
[[ -d "$app_path" ]] || fail "Application does not exist: $app_path"

app_path="${app_path:A}"
info_plist="$app_path/Contents/Info.plist"
[[ -f "$info_plist" ]] || fail "Missing Contents/Info.plist."

bundle_identifier="$(plutil -extract CFBundleIdentifier raw -o - "$info_plist")"
bundle_version="$(plutil -extract CFBundleShortVersionString raw -o - "$info_plist")"
build_number="$(plutil -extract CFBundleVersion raw -o - "$info_plist")"
executable_name="$(plutil -extract CFBundleExecutable raw -o - "$info_plist")"

[[ "$bundle_identifier" == "me.walt.diagramdown" ]] || fail "Unexpected bundle identifier: $bundle_identifier"
[[ -n "$bundle_version" ]] || fail "CFBundleShortVersionString is empty."
[[ -n "$build_number" ]] || fail "CFBundleVersion is empty."

main_executable="$app_path/Contents/MacOS/$executable_name"
d2_executable="$app_path/Contents/Helpers/d2"
[[ -x "$main_executable" ]] || fail "Missing main executable: $main_executable"
[[ -x "$d2_executable" ]] || fail "Missing D2 helper: $d2_executable"

for license_name in LICENSE MarkdownIt-LICENSE.txt Mermaid-LICENSE.txt D2-LICENSE.txt; do
  [[ -f "$app_path/Contents/Resources/$license_name" ]] || fail "Missing bundled license: $license_name"
done

main_architectures="$(lipo -archs "$main_executable")"
d2_architectures="$(lipo -archs "$d2_executable")"
[[ "$main_architectures" == "arm64" ]] || fail "Main executable must be arm64-only, found: $main_architectures"
[[ "$d2_architectures" == "arm64" ]] || fail "D2 helper must be arm64-only, found: $d2_architectures"

codesign --verify --deep --strict --verbose=2 "$app_path"
codesign --verify --strict --verbose=2 "$d2_executable"

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/diagramdown-release.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT
app_entitlements="$temporary_directory/app-entitlements.plist"
d2_entitlements="$temporary_directory/d2-entitlements.plist"
codesign -d --entitlements :- "$app_path" >"$app_entitlements" 2>/dev/null
codesign -d --entitlements :- "$d2_executable" >"$d2_entitlements" 2>/dev/null

[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$app_entitlements")" == "true" ]] || fail "The application is not sandboxed."
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.user-selected.read-write' "$app_entitlements")" == "true" ]] || fail "The application cannot read and write user-selected files."
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.network.client' "$app_entitlements")" == "true" ]] || fail "The application is missing the outgoing network entitlement required by WebKit."
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$d2_entitlements")" == "true" ]] || fail "The D2 helper is not sandboxed."
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.inherit' "$d2_entitlements")" == "true" ]] || fail "The D2 helper does not inherit the application sandbox."

app_signature="$(codesign -dvvv "$app_path" 2>&1 || true)"
d2_signature="$(codesign -dvvv "$d2_executable" 2>&1 || true)"
[[ "$app_signature" == *"runtime"* ]] || fail "The application is missing Hardened Runtime."
[[ "$d2_signature" == *"runtime"* ]] || fail "The D2 helper is missing Hardened Runtime."

if [[ "$require_adhoc" == true ]]; then
  [[ "$app_signature" == *"Signature=adhoc"* ]] || fail "The application is not ad-hoc signed."
  [[ "$d2_signature" == *"Signature=adhoc"* ]] || fail "The D2 helper is not ad-hoc signed."
  [[ "$app_signature" == *"TeamIdentifier=not set"* ]] || fail "The ad-hoc application unexpectedly has a signing team."
  [[ "$d2_signature" == *"TeamIdentifier=not set"* ]] || fail "The ad-hoc D2 helper unexpectedly has a signing team."
fi

if [[ "$require_distribution" == true ]]; then
  get_task_allow="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$app_entitlements" 2>/dev/null || print false)"
  [[ "$get_task_allow" != "true" ]] || fail "The distribution application still has the get-task-allow debugging entitlement."
  [[ "$app_signature" == *"Authority=Developer ID Application:"* ]] || fail "The application is not signed with Developer ID Application."
  [[ "$d2_signature" == *"Authority=Developer ID Application:"* ]] || fail "The D2 helper is not signed with Developer ID Application."
  [[ "$app_signature" == *"TeamIdentifier=QM6DZQY23F"* ]] || fail "The application is signed by an unexpected team."
  [[ "$d2_signature" == *"TeamIdentifier=QM6DZQY23F"* ]] || fail "The D2 helper is signed by an unexpected team."
fi

if [[ "$require_notarized" == true ]]; then
  xcrun stapler validate "$app_path"
  spctl --assess --type execute --verbose=4 "$app_path"
fi

print -- "Release validation passed: DiagramDown $bundle_version ($build_number), arm64"
