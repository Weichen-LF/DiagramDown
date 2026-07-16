# Bundled helpers

## D2

- Version: 0.7.1
- Architecture: macOS arm64
- Source archive: <https://github.com/terrastruct/d2/releases/download/v0.7.1/d2-v0.7.1-macos-arm64.tar.gz>
- Archive SHA-256: `80de85f3b0ac7d9569acac0780ed65dd994ea78969b6b230c58bbb2c6113465b`
- License: MPL-2.0

`d2` is copied to `DiagramDown.app/Contents/Helpers/d2` and signed during the app build. The checked-in helper is ad-hoc signed with Hardened Runtime and exactly the two entitlements Apple requires for sandbox inheritance.

To update it, download the official macOS arm64 archive, verify its checksum, replace `Helpers/d2`, and run:

```sh
codesign \
  --force \
  --sign - \
  --identifier me.walt.diagramdown.d2 \
  --options runtime \
  --entitlements Helpers/d2.entitlements \
  Helpers/d2
```
