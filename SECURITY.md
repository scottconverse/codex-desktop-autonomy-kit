# Security policy

## Scope

The security-sensitive parts of this repository are:

- `Setup-Autonomy.ps1`, especially its downloaded bootstrap scripts, config ownership, and
  the command-rules file it generates (`~/.codex/rules/autonomy-kit.rules`);
- `Uninstall-Autonomy.ps1`, especially configuration backup restoration;
- `elevated-dev-helper/`, especially trusted-path validation and highest-privilege actions;
- `.github/workflows/`, which executes repository-controlled tests on Windows runners.

The elevated helper is intentionally designed for an owner-controlled, single-user Windows
development machine. `RunTrustedPowerShellScript` can run any PowerShell script under its
configured trusted roots at highest privilege. That is an explicit product tradeoff, not a
claim that the helper is suitable for a shared or hostile multi-user machine.

The command-rules file (`~/.codex/rules/autonomy-kit.rules`) switches off Codex's built-in
dangerous-command classifier for this machine: force deletes stop prompting, and web-link
openers -- including `mshta` and `rundll32` with a URL, which can run code fetched from the
web -- are allowed without a prompt in any mode. This is the same single-owner-machine
tradeoff; delete the file or run `Uninstall-Autonomy.ps1` to restore Codex's built-in
behavior. Use `-SkipCommandRules` to install the kit without it.

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

