# Security policy

## Supported versions

DiagramDown has not published its first supported binary release yet. Security fixes are currently made on the latest `main` branch and will be included in the next release candidate.

## Reporting a vulnerability

Do not include vulnerability details, exploit code, credentials, or private documents in a regular issue.

The repository is currently private, and GitHub's private vulnerability reporting feature is only available to public repositories. If you already collaborate on this private repository, open an issue containing only the title “Security report request” and ask the maintainer to establish a private channel. Maintainers should transfer the report into a private draft repository security advisory before investigation.

When the repository becomes public, private vulnerability reporting will be enabled and this policy will link directly to the **Report a vulnerability** form.

Include affected versions or commits, reproduction steps, expected impact, and a minimal proof of concept when safe. Remove credentials, private documents, signing material, and unrelated personal data.

The maintainer will acknowledge the report through the agreed private channel, investigate it, and coordinate disclosure after a fix is available. Please avoid public disclosure while remediation is in progress.

## Security boundaries

Reports are especially useful when they involve:

- untrusted Markdown or SVG escaping the preview content security policy
- unexpected network access from the offline preview
- command or argument injection into the bundled D2 process
- App Sandbox or helper entitlement bypasses
- unsafe file access, export paths, or cache handling
- signing, notarization, or update-channel integrity
