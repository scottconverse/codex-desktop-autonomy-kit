# "rejected: blocked by policy"

If a Codex command fails instantly with:

```
exec_command failed: CreateProcess { message: "Rejected(... rejected: blocked by policy)" }
```

that is **not** an approval prompt and **not** a permission you are missing. It is Codex's
built-in *dangerous-command* classifier. On a machine configured for autonomy
(`approval_policy = "never"`), Codex has nobody to ask, so it refuses the command outright.
The refusal takes ~0 seconds and no model reviews it.

## What is on the list

Only two kinds of command trigger it:

1. **Force deletes** -- a delete together with a force flag:
   - PowerShell: `Remove-Item` / `ri` / `rm` / `del` / `erase` / `rd` / `rmdir` with `-Force`
   - cmd: `del` / `erase` with `/f`; `rd` / `rmdir` with both `/s` and `/q`
   - Unix-style: `rm -f` / `--force` (also behind `sudo`, `env`, `trap`)
2. **Web-link openers** -- a command containing an `http://` or `https://` address together
   with `Start-Process`, `start`, `saps`, `Invoke-Item`, `ii`, `explorer`, `mshta`,
   `rundll32`, or a browser (`chrome`, `msedge`, `firefox`, `iexplore`), or ShellExecute /
   Shell.Application.

Deletes **without** the force flag, and `[System.IO.File]::Delete()` /
`[System.IO.Directory]::Delete()`, are not on the list and run normally.

## The fix this kit ships

`Install-Autonomy.cmd` writes `~/.codex/rules/autonomy-kit.rules`, an execpolicy allow-list
that overrides the classifier for every pattern above, using shell paths discovered on this
machine. **An explicit allow-rule beats the built-in list.** After installing, start a new
Codex chat (Codex reads its rules when a chat starts) and the command runs.

Check status any time with `Doctor-Autonomy.cmd`: it reports whether the rules file is
present, parser-safe (no UTF-8 BOM), current with this kit, and whether Codex has started
using a shell path the file does not yet cover (which happens after a Codex update moved its
bundled PowerShell -- re-run `Install-Autonomy.cmd` to refresh).

## If you still hit it

1. **Re-run `Install-Autonomy.cmd`.** This regenerates the rules for the current machine,
   including any new shell path, and re-validates with Codex's own checker.
2. **Confirm a new chat.** Rules load at chat start; an already-open chat may still be using
   the old set.
3. **Read the rejection to see which program was blocked.** The quoted command begins with
   the shell's full path. If `Doctor-Autonomy.cmd` lists it as an *uncovered shell*, step 1
   fixes it.
4. **Meanwhile, keep moving.** The same delete without `-Force`, or
   `[System.IO.File]::Delete()` / `[System.IO.Directory]::Delete()`, is not blocked.

## How to verify by hand

Codex ships its own policy checker. Point it at the rules file and a sample command; it must
print `"decision":"allow"`:

```
codex execpolicy check --rules "<codex home>\rules\autonomy-kit.rules" Remove-Item x -Recurse -Force
```

## What switching the list off means

These commands no longer prompt in any mode, including "ask me". That includes Codex opening
a web link in your logged-in browser, and `mshta` / `rundll32` with a URL (which can run code
fetched from the web). This kit is for an owner-controlled, single-user development machine;
that is the deliberate tradeoff. To restore Codex's built-in behavior, delete the rules file
or run `Uninstall-Autonomy.cmd`.
