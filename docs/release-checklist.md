# DiagramDown release checklist

Use this checklist for every public community release. The current channel is Apple Silicon-only, ad-hoc signed, and not notarized by Apple.

## 1. Prepare the version

- [ ] Start from an up-to-date branch based on `main`.
- [ ] Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project.
- [ ] Move user-visible changes from `Unreleased` into the dated version section in `CHANGELOG.md`.
- [ ] Add `docs/releases/<version>.md` with requirements, highlights, limitations, checksum instructions, and Gatekeeper guidance.
- [ ] Confirm the release notes say that the binary is ad-hoc signed and not notarized.

## 2. Validate the release candidate

- [ ] Run `./Scripts/test.sh`.
- [ ] Run `./Scripts/package-release.sh --allow-dirty --expected-version <version>` to validate the candidate before commit.
- [ ] Confirm `validate-release.sh` reports the expected version, build, arm64 architecture, signatures, entitlements, Hardened Runtime, and licenses.
- [ ] Inspect the final diff and make sure no build products, credentials, local paths, or test documents were added.

GUI automation and Computer Use are not part of this release gate. The combined `docs/examples/all-features.md` document remains available for optional human checks.

## 3. Merge the preparation pull request

- [ ] Push the release-preparation branch and open a pull request.
- [ ] Wait for the required CI and CodeQL checks.
- [ ] Merge the pull request into `main`.
- [ ] Pull the merged `main` and confirm the worktree is clean.

## 4. Publish

Create and push an annotated tag from the merged `main` commit:

```sh
git tag -a v0.21.0 -m "Release DiagramDown 0.21.0"
git push origin v0.21.0
```

The `Release` GitHub Actions workflow will rerun tests, build the package, validate it, and create the GitHub Release.

- [ ] Confirm the workflow succeeds.
- [ ] Confirm the Release is public and is not marked as a draft or prerelease.
- [ ] Confirm both `DiagramDown-<version>-arm64.zip` and its `.sha256` file are attached.
- [ ] Confirm the release notes render the unnotarized-build warning prominently.

## 5. Verify the published assets

Download the published files into a temporary directory and run:

```sh
shasum -a 256 -c DiagramDown-0.21.0-arm64.zip.sha256
```

- [ ] Confirm the checksum reports `OK`.
- [ ] Confirm `gh release view v0.21.0` reports the intended tag, title, notes, and assets.
- [ ] Confirm the README's latest-release link resolves to the new release.

## 6. After publication

- [ ] Leave the release immutable unless an asset is proven corrupt; publish a patch version instead of silently replacing a working asset.
- [ ] Record defects as GitHub issues and prioritize data loss, crashes, save failures, security problems, and rendering blockers.
- [ ] Put follow-up changes under `Unreleased` in `CHANGELOG.md`.
