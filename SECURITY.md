# Security policy

## Scope

The security-sensitive parts of this repository are:

- `Setup-Autonomy.ps1`, especially its downloaded bootstrap scripts and config ownership;
- `Uninstall-Autonomy.ps1`, especially configuration backup restoration;
- `elevated-dev-helper/`, especially trusted-path validation and highest-privilege actions;
- `.github/workflows/`, which executes repository-controlled tests on Windows runners.

The elevated helper is intentionally designed for an owner-controlled, single-user Windows
development machine. `RunTrustedPowerShellScript` can run any PowerShell script under its
configured trusted roots at highest privilege. That is an explicit product tradeoff, not a
claim that the helper is suitable for a shared or hostile multi-user machine.

## Reporting

Please do not publish exploit details in a public issue before coordination. Use GitHub's
private vulnerability-reporting or security-advisory flow for this repository when available.
If that flow is not enabled, contact the repository maintainer through the GitHub profile and
include the affected version, operating-system details, reproduction steps, and the minimum
safe disclosure needed to reproduce the issue.

## Supported security surface

Only the current release line is expected to receive security fixes. Before reporting a
possible issue, check the current tag and changelog. Do not include real Codex configuration,
tokens, credentials, private repositories, or other machine-sensitive data in a report.

