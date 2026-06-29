# Codex Elevated Development Helper

This kit is a reusable Windows helper pattern for machines where Codex Desktop cannot launch
its shell with an administrator token.

## What It Does

- Installs a Windows Scheduled Task named `CodexElevatedDevHelper`.
- The task runs `ElevatedDevHelper.ps1` with highest privileges.
- Codex or a normal user process can queue structured JSON jobs and trigger the task.
- The helper runs supported development actions and writes JSON results/logs.

## What It Does Not Do

This is not an unrestricted admin command broker. It intentionally refuses arbitrary commands. It supports named development actions only:

- `CheckAdmin`
- `WingetInstall`
- `WingetUpgrade`
- `RunTrustedPowerShellScript`
- `StartService`
- `StopService`
- `RestartService`
- `OpenDevFirewallPort`
- `RegisterDevScheduledTask`

## Install

The one-time installer must be launched from an elevated PowerShell session because Windows UAC controls creation of highest-privilege scheduled tasks.

For a click-driven install on this machine, double-click `Install-ElevatedDevHelper-AsAdmin.cmd` and approve the Windows UAC prompt. The launcher opens an elevated PowerShell process, runs the installer, waits for the self-test, and closes the elevated window when finished.

The elevated installer window closes after completion. A successful install writes an install log and a self-test result where `is_admin` is `true`.

If a diagnostic shows `Elevated=False` and `Integrity=Medium Mandatory Level`, that diagnostic was run in a non-elevated process. That is expected for normal Codex Desktop shells, but not for the elevated installer window or the scheduled-task helper result.

After installation, the helper root defaults to:

`C:\dev\CodexElevatedHelper`

The queue, result, failure, and log folders are:

- `C:\dev\CodexElevatedHelper\queue`
- `C:\dev\CodexElevatedHelper\done`
- `C:\dev\CodexElevatedHelper\failed`
- `C:\dev\CodexElevatedHelper\logs`

The installer also writes:

- `C:\dev\CodexElevatedHelper\install-log.txt`
- `C:\dev\CodexElevatedHelper\install-state.json`

Use `Test-ElevationState.ps1` only to inspect the process where it is launched. It does not prove the scheduled task helper is elevated unless it is run by the helper itself.

## Reuse On Other Machines

Copy this folder to another personal development machine, review the scripts, then perform the
same one-time elevated setup there. Trusted script roots resolve from the current
`$env:USERPROFILE` plus `C:\dev`, so the helper is not tied to one Windows account name. The
GEN5 addendum can be appended to that machine's persistent Codex instructions.

## Notes On Inline Elevation

Prompt text cannot bypass Windows UAC, app policy, or Codex Desktop's enforced permissions.
If the desktop app cannot run its inline shell elevated, the correct path is this helper: a
one-time owner-approved scheduled task that runs with highest privileges and accepts bounded,
structured development jobs.

## Safety Model

The helper accepts only structured jobs and known action names. It logs every job start,
success, and failure. It restricts trusted script execution to local development roots. It is
intended for reversible development infrastructure, not destructive system administration.

`RunTrustedPowerShellScript` intentionally creates a no-per-action-UAC local-admin path for
scripts under trusted development roots. That is the accepted single-owner development trade:
powerful enough for SDKs, installers, services, and firewall checks, but still structured and
logged.

Expand the action list only when a real development task needs it, and keep each action structured instead of adding a generic unrestricted command action.
