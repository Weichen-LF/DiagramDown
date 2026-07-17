# Security policy

## Supported versions

DiagramDown `0.17.x` and the latest `main` branch are supported. Security fixes are released as patch versions when they affect the public community build.

## Reporting a vulnerability

Do not include vulnerability details, exploit code, credentials, or private documents in a regular issue.

Use GitHub's private [Report a vulnerability](https://github.com/Weichen-LF/DiagramDown/security/advisories/new) form. It creates a private security advisory that is visible only to the reporter and repository maintainers while the report is investigated.

Include affected versions or commits, reproduction steps, expected impact, and a minimal proof of concept when safe. Remove credentials, private documents, signing material, and unrelated personal data.

The maintainer will acknowledge the report in the private advisory, investigate it, and coordinate disclosure after a fix is available. Please avoid public disclosure while remediation is in progress.

## Security boundaries

Reports are especially useful when they involve:

- untrusted Markdown or SVG escaping the preview content security policy
- unexpected network access from the offline preview
- command or argument injection into the bundled D2 process
- App Sandbox or helper entitlement bypasses
- unsafe file access, export paths, or cache handling
- signing, notarization, or update-channel integrity
