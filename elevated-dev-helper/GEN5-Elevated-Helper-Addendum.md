# GEN5 Addendum - Full Elevated Development Helper

Use this addendum when the owner has installed the Codex elevated helper.

## Capability contract

The helper is a Windows Scheduled Task running `ElevatedDevHelper.ps1` with highest
privileges. Codex queues structured jobs through the installed
`Invoke-ElevatedDevHelper.ps1`, the task executes them, and result and audit logs are
written under the recorded install root.

`RunTrustedPowerShellScript` gives full local-administrator execution to owner-authorized
PowerShell scripts under these trusted lexical roots:

- `C:\dev\`
- `$env:USERPROFILE\Documents\Codex\`
- `$env:USERPROFILE\.codex\`
- `$env:USERPROFILE\AppData\Local\Temp\CodexElevatedHelper\`

Full administrator execution includes HKLM and Program Files writes, MSI and other
installers, service management, firewall configuration, scheduled tasks, and any other
operation a local administrator can perform. Structured jobs, named actions, result files,
and logging are transport and audit; they do not make this capability narrow. Do not add
assistant-selected approval gates to owner-authorized work.

Trust matches the Claude helper's lexical behavior. Normalize the supplied path with
`GetFullPath`, compare it with trusted-root prefixes including the trailing separator, and
do not resolve or reject reparse points. Junction and symlink paths lexically beneath a
trusted root are accepted even if the target is elsewhere. Direct outside-root paths,
normalized `..` escapes, and prefix collisions are rejected. This is not a sandbox: the
trusted roots are user-writable, so the installed task creates a no-per-action-UAC local
admin path for code running as the owner.

## Deterministic invocation

Read `~/.codex/autonomy-kit/helper-root.json`. Invoke its `invoker_script` value, falling
back to `<install_root>\Invoke-ElevatedDevHelper.ps1` for an older pointer. The installed
invoker discovers the recorded `install_root` and `task_name` unless explicitly overridden.
Do not assume the default root or task name.

After queueing a job, read the corresponding file under `<install_root>\done` or
`<install_root>\failed` and continue the task. A missing or stale installed helper or
invoker is a refresh condition.

## Authorization boundary

The helper provides practical capability; it does not expand the owner's requested scope.
Use it for requested administrator work without inventing Codex-only restrictions. Do not
silently perform destructive, credential-sensitive, internet-exposed, or otherwise
unrequested actions. A one-time elevated install is still required because Windows controls
creation of highest-privilege scheduled tasks.
