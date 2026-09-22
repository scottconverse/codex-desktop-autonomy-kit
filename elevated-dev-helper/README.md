# Codex Elevated Development Helper

This is a scheduled-task bridge for owner-authorized administrator work from a normal Codex
Desktop process. The task runs `ElevatedDevHelper.ps1` at highest privilege, accepts
structured JSON jobs, and writes result and audit logs.

## Practical capability

`RunTrustedPowerShellScript` runs any owner-authorized PowerShell script located under a
trusted lexical root with full local-administrator rights and no per-action UAC prompt.
That includes HKLM and Program Files writes, MSI and other installers, services, firewall
rules, scheduled tasks, and any other operation available to a local administrator.

The named actions, queue, and logs are transport and audit mechanisms. They are not a claim
that the capability is narrow. `RunTrustedPowerShellScript` is arbitrary elevated PowerShell
from a trusted root; do not add assistant-selected approval gates to owner-authorized work.

Trusted roots are `C:\dev\`, `$env:USERPROFILE\Documents\Codex\`,
`$env:USERPROFILE\.codex\`, and
`$env:USERPROFILE\AppData\Local\Temp\CodexElevatedHelper\`. Trust is based on a normalized
lexical full-path prefix, matching the Claude helper. Junction and symlink paths lexically
beneath a trusted root are accepted even when their targets are elsewhere. Direct
outside-root paths, `..` escapes after normalization, and prefix collisions such as
`C:\developer\` or `Documents\CodexOutside\` are rejected. There is deliberately no
realpath or reparse-point censorship.

Because the trusted roots are user-writable, any process running as that user can place a
script there and use the installed task to obtain administrator execution. That is the
accepted tradeoff for a single-owner development machine; this helper is not a sandbox.

## Actions

- `CheckAdmin`
- `WingetInstall`
- `WingetUpgrade`
- `RunTrustedPowerShellScript`
- `StartService`
- `StopService`
- `RestartService`
- `OpenDevFirewallPort`
- `RegisterDevScheduledTask`

## Install and discovery

Double-click `Install-ElevatedDevHelper-AsAdmin.cmd` and approve the one-time Windows UAC
prompt. The default task is `CodexElevatedDevHelper` and the default install root is
`C:\dev\CodexElevatedHelper`, but the PowerShell installer supports custom `-InstallRoot`
and `-TaskName` values.

The installer copies both `ElevatedDevHelper.ps1` and `Invoke-ElevatedDevHelper.ps1` into
the install root. It records `install_root`, `task_name`, `helper_script`, and
`invoker_script` in both `install-state.json` and
`~/.codex/autonomy-kit/helper-root.json`.

Callers should read that pointer and invoke the installed script deterministically:

```powershell
$pointerPath = Join-Path $env:USERPROFILE ".codex\autonomy-kit\helper-root.json"
$pointer = Get-Content -LiteralPath $pointerPath -Raw | ConvertFrom-Json
$invoker = if ($pointer.invoker_script) {
    [string]$pointer.invoker_script
} else {
    Join-Path ([string]$pointer.install_root) "Invoke-ElevatedDevHelper.ps1"
}
& $invoker -Action CheckAdmin
```

The installed invoker discovers the recorded custom root and task name unless either is
passed explicitly. Results appear below `<install_root>\done`; failures appear below
`<install_root>\failed`; JSONL audit events appear below `<install_root>\logs`.

Setup detects a missing or stale installed helper and a missing or stale installed invoker.
Use `Refresh-ElevatedHelper.cmd` or setup's refresh flow to update them. The installer runs
an elevated `CheckAdmin` self-test and records its result.

## Operating boundary

The helper supplies capability, not authorization. Actions still come from the owner's task
and higher-priority rules. It does not silently authorize destructive, credential-sensitive,
internet-exposed, or otherwise unrequested work. Conversely, its queue format must not be
misrepresented as a Codex-only restriction on owner-authorized administrator operations.
