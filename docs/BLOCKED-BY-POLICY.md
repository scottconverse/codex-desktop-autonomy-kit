# "rejected: blocked by policy"

If a Codex command fails instantly with:

```
exec_command failed: CreateProcess { message: "Rejected(... rejected: blocked by policy)" }
```

Codex refused to launch the command. The refusal happens before the shell runs, takes ~0
seconds, and no model reviews it. On a machine configured for autonomy
(`approval_policy = "never"`), Codex has nobody to ask, so a command it would otherwise
prompt for is refused outright.

**A policy rejection is its own thing.** It is not:

- a Windows ACL / access-denied failure (those come from the command after it starts);
- a missing executable (the shell was found; Codex declined to start it);
- by itself proof of a runtime mismatch (see below -- a mismatch is one *candidate* cause).

Treat it as Codex enforcing its command policy. Report the rejected command exactly. Do not
respell the command or route it through a different program to get past the rejection; if
the policy should be different on your machine, change the policy deliberately (this page
describes how the kit's rules do that) rather than working around it one command at a time.

## What Codex's built-in list covers

As far as this kit has observed, two kinds of command trigger it:

1. **Force deletes** -- a delete together with a force flag:
   - PowerShell: `Remove-Item` / `ri` / `rm` / `del` / `erase` / `rd` / `rmdir` with `-Force`
   - cmd: `del` / `erase` with `/f`; `rd` / `rmdir` with both `/s` and `/q`
   - Unix-style: `rm -f` / `--force` (also behind `sudo`, `env`, `trap`)
2. **Web-link openers** -- a command containing an `http://` or `https://` address together
   with `Start-Process`, `start`, `saps`, `Invoke-Item`, `ii`, `explorer`, `mshta`,
   `rundll32`, or a browser (`chrome`, `msedge`, `firefox`, `iexplore`), or ShellExecute /
   Shell.Application.

This list is an observation of Codex's behavior, not a specification. Codex can change it,
and a rejection can have a cause this page does not list.

## What this kit installs

`Install-Autonomy.cmd` writes `~/.codex/rules/autonomy-kit.rules`, an execpolicy allow-list
intended to override the built-in list for the patterns above. It contains:

- one path-only rule per shell executable discovered on the machine (Codex's bundled
  PowerShell, Windows PowerShell, `cmd.exe`), each named by **absolute path**;
- name rules for the delete commands and link openers.

Codex reads its rules when a chat starts, so a chat that was already open keeps the rules it
started with.

## Known limitations

**The rules go stale when Codex's shell moves.** The shell rules name an absolute path, and
Codex's bundled PowerShell does not stay put. It has shipped under the per-user cache
(`%USERPROFILE%\.cache\codex-runtimes\...`) and, more recently, as a versioned packaged
runtime (`%ProgramFiles%\WindowsApps\OpenAI.CodexPrimaryRuntime.v<version>_...`), whose
folder name changes with every runtime update. After such a move:

- the old rules file is still on disk;
- every executable it lists may still exist (the old runtime is not always removed);
- Codex launches commands through an executable the file does not list.

Nothing about the file's presence, or its listed files existing, reveals this. Setup
discovers installed packaged runtimes as well as cached ones (earlier versions found a
packaged runtime only after a session had already used it), but rules written today still go
stale at the next runtime update, until you re-run `Install-Autonomy.cmd` and start a new
chat.

**Coverage is not the same as acceptance.** Setup validates the file with Codex's own
`codex execpolicy check`, which confirms the file parses and that its rules match sample
commands. That is not a command run inside a Codex chat. This kit does not claim that a
given command will be accepted; that is shown only by the command running in a chat.

**A mismatch is a candidate cause, not a diagnosis.** If Codex rejected a command launched
through an executable the rules do not list, the missing rule is consistent with the
rejection. It does not prove the rejection would not have happened with the rule present.

## Checking what the installed rules cover

Run `Doctor-Autonomy.cmd`. Its **Codex runtime compatibility** section reports each of these
separately:

| Line | Meaning |
|------|---------|
| `configured executables` | Each executable the rules list, and whether it exists on disk. A missing file is reported as missing, not as a mismatch. |
| `active runtime` | `KNOWN` with the executable Codex actually launched and the evidence (the process tree when Doctor runs inside Codex; otherwise the most recent launch in the newest session log), or `UNKNOWN` with whatever evidence exists. A path that only appears in prose or output is not counted as a launch. |
| `rules list active runtime` | `MATCH`, `MISMATCH`, or `UNKNOWN`. |
| `new Codex chat required` | `REQUIRED` when the rules were written after that session started. |
| `installed runtime NOT listed` | An installed Codex runtime the rules do not list (for example a newer runtime no session has used yet). |
| `policy rejections (that session)` | Rejections recorded in that session's log, counted on their own line. |
| `overall` | `PASS`, `MISMATCH`, `RELOAD_REQUIRED`, `UNKNOWN`, or `NOT_INSTALLED`. |

`UNKNOWN` is reported whenever the active executable cannot be determined reliably: no
session logs, a newest session that ran no commands, a log too large to read, or a
last-launched executable that no longer exists. It is never rounded up to `PASS`.

`PASS` means only: the rules list the executable Codex launched, that executable exists,
and that session started after the rules were written.

Doctor is read-only. It never regenerates, rewrites, or widens the rules, whatever it finds.

## If Codex rejects a command

1. **Record it.** Keep the exact rejected command and the time.
2. **Run `Doctor-Autonomy.cmd`** and read the runtime compatibility section.
   - `MISMATCH`: the rules do not list the executable Codex launches. If you want the kit's
     rules to cover it, re-run `Install-Autonomy.cmd` yourself, then start a new chat. This
     is a decision to change policy on your machine; nothing does it for you.
   - `RELOAD_REQUIRED`: start a new Codex chat.
   - `UNKNOWN`: run any command in a new Codex chat, then run Doctor again.
   - `PASS`, and the command is still rejected: the rejection has some other cause. The
     kit has no further remedy; treat it as a restriction that remains in force.
3. **Do not work around it.** Do not respell the command, drop a flag to dodge the match, or
   route the same action through another program or API to get past the rejection.

## Verifying a rule by hand

Codex ships its own policy checker. It reports which rule, if any, matches a command:

```
codex execpolicy check --rules "<codex home>\rules\autonomy-kit.rules" "<full path to the shell Codex uses>" -Command "Get-Date"
```

`"decision":"allow"` with a matched rule means the file has a rule for that executable. An
empty `matchedRules` means it does not.

## What switching the list off means

Where the rules take effect, the listed commands no longer prompt in any mode, including
"ask me". That includes Codex opening a web link in your logged-in browser, and `mshta` /
`rundll32` with a URL (which can run code fetched from the web). This kit is for an
owner-controlled, single-user development machine; that is the deliberate tradeoff. To
restore Codex's built-in behavior, delete the rules file or run `Uninstall-Autonomy.cmd`.
