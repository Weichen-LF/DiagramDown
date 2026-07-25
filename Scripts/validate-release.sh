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
[[ -x "$main_executable" ]] || fail "Missing main executable: $main_executable"
[[ ! -e "$app_path/Contents/Helpers/d2" ]] || fail "A bundled D2 executable is still present."

for license_name in \
  LICENSE \
  Prettier-LICENSE.txt \
  Prettier-THIRD-PARTY-NOTICES.txt \
  SwiftMarkdown-LICENSE.txt \
  SwiftCMark-LICENSE.txt \
  SwiftTreeSitter-LICENSE.txt \
  TreeSitter-LICENSE.txt \
  TreeSitterSwift-LICENSE.txt \
  TreeSitterLua-LICENSE.txt \
  TreeSitterYAML-LICENSE.txt \
  TreeSitterJavaScript-LICENSE.txt \
  TreeSitterTypeScript-LICENSE.txt \
  TreeSitterJSON-LICENSE.txt \
  TreeSitterBash-LICENSE.txt
do
  [[ -f "$app_path/Contents/Resources/$license_name" ]] || fail "Missing bundled license: $license_name"
done

for runtime_name in formatter.js prettier.js markdown.js; do
  [[ -f "$app_path/Contents/Resources/$runtime_name" ]] || fail "Missing bundled runtime asset: $runtime_name"
done

for removed_runtime_name in \
  preview.html preview.css preview.js markdown-it.min.js highlight.min.js \
  formatter.html renderer.html renderer.js mermaid.min.js
do
  [[ ! -e "$app_path/Contents/Resources/$removed_runtime_name" ]] || fail "Legacy preview runtime is still bundled: $removed_runtime_name"
done

linked_frameworks="$(otool -L "$main_executable")"
[[ "$linked_frameworks" != *"WebKit.framework"* ]] || fail "The application still links WebKit."
[[ "$linked_frameworks" != *"SVGView"* ]] || fail "The application still links SVGView."

for grammar_bundle in \
  TreeSitterBash_TreeSitterBash.bundle \
  TreeSitterJSON_TreeSitterJSON.bundle \
  TreeSitterJavaScript_TreeSitterJavaScript.bundle \
  TreeSitterLua_TreeSitterLua.bundle \
  TreeSitterSwift_TreeSitterSwift.bundle \
  TreeSitterTypeScript_TreeSitterTSX.bundle \
  TreeSitterTypeScript_TreeSitterTypeScript.bundle \
  TreeSitterYAML_TreeSitterYAML.bundle
do
  [[ -d "$app_path/Contents/Resources/$grammar_bundle" ]] || fail "Missing Tree-sitter grammar resources: $grammar_bundle"
  [[ -f "$app_path/Contents/Resources/$grammar_bundle/Contents/Resources/queries/highlights.scm" ]] || fail "Missing highlights query in $grammar_bundle"
done

example_document="$app_path/Contents/Resources/DiagramDown-Example.md"
[[ -f "$example_document" ]] || fail "Missing bundled example document."
grep -q '^```mermaid$' "$example_document" || fail "The bundled example does not contain Mermaid source."
grep -q '^```d2$' "$example_document" || fail "The bundled example does not contain D2 source."

main_architectures="$(lipo -archs "$main_executable")"
[[ "$main_architectures" == "arm64" ]] || fail "Main executable must be arm64-only, found: $main_architectures"

codesign --verify --deep --strict --verbose=2 "$app_path"

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/diagramdown-release.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT
app_entitlements="$temporary_directory/app-entitlements.plist"
codesign -d --entitlements :- "$app_path" >"$app_entitlements" 2>/dev/null

if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$app_entitlements" >/dev/null 2>&1; then
  fail "The application is unexpectedly sandboxed."
fi
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.network.client' "$app_entitlements" >/dev/null 2>&1; then
  fail "The obsolete WebKit network entitlement is still present."
fi

app_signature="$(codesign -dvvv "$app_path" 2>&1 || true)"
[[ "$app_signature" == *"runtime"* ]] || fail "The application is missing Hardened Runtime."

if [[ "$require_adhoc" == true ]]; then
  [[ "$app_signature" == *"Signature=adhoc"* ]] || fail "The application is not ad-hoc signed."
  [[ "$app_signature" == *"TeamIdentifier=not set"* ]] || fail "The ad-hoc application unexpectedly has a signing team."
fi

if [[ "$require_distribution" == true ]]; then
  get_task_allow="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$app_entitlements" 2>/dev/null || print false)"
  [[ "$get_task_allow" != "true" ]] || fail "The distribution application still has the get-task-allow debugging entitlement."
  [[ "$app_signature" == *"Authority=Developer ID Application:"* ]] || fail "The application is not signed with Developer ID Application."
  [[ "$app_signature" == *"TeamIdentifier=QM6DZQY23F"* ]] || fail "The application is signed by an unexpected team."
fi

if [[ "$require_notarized" == true ]]; then
  xcrun stapler validate "$app_path"
  spctl --assess --type execute --verbose=4 "$app_path"
fi

print -- "Release validation passed: DiagramDown $bundle_version ($build_number), arm64"
