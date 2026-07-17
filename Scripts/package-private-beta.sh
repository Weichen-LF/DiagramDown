#!/bin/zsh

set -euo pipefail

print -u2 -- "package-private-beta.sh is deprecated; using package-release.sh."
exec "${0:A:h}/package-release.sh" "$@"
