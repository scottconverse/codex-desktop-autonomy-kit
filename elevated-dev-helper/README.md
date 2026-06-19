# Codex Elevated Development Helper

This kit is a reusable Windows helper pattern for machines where Codex Desktop cannot launch its shell with an administrator token.

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

For a click-driven install on this machine, double-click `Install-ElevatedDevHelper-AsAdmin.cmd` and approve the Windows UAC prompt. The launcher opens an elevated PowerShell process and runs the installer.

After installation, the helper root defaults to:

`C:\dev\CodexElevatedHelper`

The queue, result, failure, and log folders are:

- `C:\dev\CodexElevatedHelper\queue`
- `C:\dev\CodexElevatedHelper\done`
- `C:\dev\CodexElevatedHelper\failed`
- `C:\dev\CodexElevatedHelper\logs`

## Reuse On Other Machines

Copy this folder to another personal development machine, review the paths in the scripts, then perform the same one-time elevated setup there. The GEN5 addendum can be appended to that machine's persistent Codex instructions.

## Safety Model

The helper accepts only structured jobs and known action names. It logs every job start, success, and failure. It restricts trusted script execution to local development roots. It is intended for reversible development infrastructure, not destructive system administration.

Expand the action list only when a real development task needs it, and keep each action structured instead of adding a generic unrestricted command action.
