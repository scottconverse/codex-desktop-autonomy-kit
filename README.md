# Codex Desktop Autonomy Kit

**Version 1.7.0 - Windows** - a click-first setup kit for configuring Codex Desktop toward
maximum practical software-development autonomy on Windows development machines. See
[CHANGELOG.md](CHANGELOG.md).

[Landing page](docs/index.html) | [User manual](docs/USER-MANUAL.md) | [Security policy](SECURITY.md) | [Elevated helper details](elevated-dev-helper/README.md)

![Codex Desktop Autonomy Kit architecture](docs/assets/codex-autonomy-architecture.svg)

## What It Does

Codex Desktop Autonomy Kit turns a Windows Codex Desktop install into a more capable local
development collaborator. It stages persistent Codex instructions, configures the Codex
sandbox for full local development access, installs common user-scope tooling, and optionally
installs an audited elevated helper that provides owner-authorized local-administrator execution.

It also installs a capability self-assessment rule and skill. The most common failure of an
autonomous coding agent is not a missing permission -- it is inventing one, then stopping to
ask for access it already has. The kit gives the agent a probe protocol and a standing rule:
test the limit before asserting it, name real blockers precisely, and keep working.

The kit is designed around a no-CLI normal path: clone or download the repo, double-click
`Install-Autonomy.cmd`, approve Windows UAC only when the elevated helper needs setup or
refresh, then restart Codex Desktop.

## Contents

- `Setup-Autonomy.ps1` - one-command fresh-machine bootstrap. Installs common user-scope
  development tooling, stages Codex autonomy profiles, creates first-run config when no
  config exists, and triggers the elevated helper installer if needed.
- `Install-Autonomy.cmd` - double-click one-stop installer/updater for normal use.
- `Doctor-Autonomy.ps1` - read-only status dashboard for toolchain, config, staged profile
  freshness, helper task/folder state, and installed-helper parity.
- `Doctor-Autonomy.cmd` - double-click doctor/status wrapper.
- `Uninstall-Autonomy.ps1` - reverses the config layer and optionally unregisters the
  elevated helper. Leaves the general-purpose toolchain alone.
- `Uninstall-Autonomy.cmd` - double-click uninstall wrapper. Prompts separately before
  unregistering the elevated helper task.
- `Refresh-ElevatedHelper.cmd` - double-click elevated-helper refresh wrapper.
- `Run-Tests.cmd` - double-click test runner wrapper.
- `CODEX-Desktop-Core.md` - compact standing instructions for everyday speed.
- `GEN5-Codex-Desktop-Autonomous-Software-Development.md` - full/depth Codex instruction
  profile for broad or high-blast-radius work.
- `config.autonomy.example.toml` - example Codex autonomy config for manual merge.
- `elevated-dev-helper/` - reusable, audited full-administrator helper for Windows machines where Codex Desktop cannot launch its shell with an admin token.
- `tests/` - capability harness, behavioral test plan, and hardcoded-path regression guard.
- `skills/capability-check/` - shipped skill that makes an agent probe its own access instead of asserting limits it never tested.
- `templates/AGENTS-capability-section.md` - the marker-delimited capability rule Setup appends to your global `AGENTS.md`.
- `SECURITY.md` - reporting path and the elevated-helper threat-model boundary.

## Capability Self-Assessment

An agent that believes it cannot write outside its workspace will ask for permission it does
not need, or hand back a blocker that is not real. That costs more time than almost any other
failure mode, and prose alone does not fix it -- a model can rationalize past an instruction.

The kit fixes it with evidence instead:

- **A probe protocol.** The `capability-check` skill tells the agent to actually run
  `Test-Path`, attempt a real write, try the command -- rather than reasoning about what a
  sandbox probably allows. Three seconds of testing replaces an argument.
- **Failure-mode separation.** A policy veto (`rejected: blocked by policy`) is a spelling
  problem: reformat and retry. A real limit (ACL, UAC declined, file lock, missing tool) gets
  named precisely. An imagined limit is the common case, and gets tested away.
- **A standing rule in `AGENTS.md`.** The installer appends it inside begin/end markers, only
  if absent, backing up first. Content you wrote there is never rewritten.
- **A section in `CODEX-Desktop-Core.md`**, so the rule travels wherever the profile is used.

Trigger it explicitly with the phrase "capability check" or the `$capability-check` skill.

## Intended Use

Use the compact core as the persistent Codex instruction baseline for personal development
machines. It authorizes Codex to inspect, edit, install, configure, build, test, debug,
retry, verify, and clean up ordinary development work within higher-priority rules and real
OS/app boundaries. The core points to GEN5 for deeper operating detail when the task has more
blast radius.

Use the elevated helper when a non-admin Codex Desktop session needs owner-authorized
local-administrator execution. Structured jobs and logs are its transport and audit trail,
not a limit on what a trusted PowerShell script can do.

## Quick Start

From a clean Windows/Codex box:

1. **Back up your existing Codex config first** (skip if this is a fresh machine with no
   config):

   ```powershell
   Copy-Item "$env:USERPROFILE\.codex\config.toml" "$env:USERPROFILE\.codex\config.toml.my-backup" -ErrorAction SilentlyContinue
   ```

   The installer backs up before any overwrite it performs and will not replace a config
   it did not generate. This step is belt-and-braces: it is the copy *you* control, and it
   costs nothing.

2. Clone or download the kit, then double-click:

   `Install-Autonomy.cmd`

3. Restart Codex Desktop so PATH and config changes load.

### What setup will and will not do to your config

`Setup-Autonomy.ps1` creates `~/.codex/config.toml` only when it does not exist. If one exists,
it replaces it only when the file is provably kit-owned:

- **It matches the exact template the kit generates**, optionally differing only in the kit's
  own `# version = "..."` line.
- **You passed `-ForceConfig`** explicitly.

Anything else -- including a config that carries the kit marker but which you have edited
since -- is left byte-for-byte unchanged, and setup stages files under
`~/.codex/autonomy-kit/` for manual merge. A backup is taken before any overwrite that does
happen. When an existing config is overwritten, setup records that exact backup path and
SHA-256 in `~/.codex/autonomy-kit/config-backup-manifest.json`; uninstall restores only that
recorded backup, never an arbitrary newest `.bak-*` file.

The kit does **not** use substring or "looks like a template" heuristics to decide ownership.
v1.6.1 fixed exactly that: an earlier version treated a config as kit-managed when it merely
contained the core heading and an `approval_policy = "never"` line, and could overwrite a
heavily customized config. A false positive here costs your entire configuration, so the test
is anchored and the real-world custom shapes are regression-tested.

Besides config, setup stages the instruction profiles under `~/.codex/autonomy-kit`, installs
the `capability-check` skill, and appends the capability rule to `~/.codex/AGENTS.md` (keeping
any content you already had there).

The two remote bootstrap scripts for uv and Scoop are downloaded to temporary files and must
match release-pinned SHA-256 values before they run. A missing pin or mismatch refuses to
execute the downloaded script.

Status check: double-click `Doctor-Autonomy.cmd`. Doctor is read-only: it reports directory
presence without creating write-probe files. It also reports whether the capability rule and
skill are installed.

If the elevated helper is stale, the installer offers to refresh it in the same flow. Approve
the Windows administrator prompt when you choose yes. The elevated installer window closes
after the helper install and self-test complete.

## Elevated Helper Setup

The helper still requires a one-time owner-approved Windows UAC step on each machine. See:

`elevated-dev-helper/README.md`

The helper executes named, structured actions and logs every result. Invoke the installed
copy by reading `~/.codex/autonomy-kit/helper-root.json` and running its `invoker_script`
value (or `<install_root>\Invoke-ElevatedDevHelper.ps1` as the fallback). This preserves
custom install roots and task names end to end.

Be clear about what that does and does not mean. One of the supported actions,
`RunTrustedPowerShellScript`, runs **any PowerShell script located under a trusted
development root**, with arguments you supply, from a task running at highest
privilege. It provides full local-administrator execution: trusted scripts can modify HKLM
and Program Files, run MSI and other installers, manage services, firewall rules, scheduled
tasks, and perform other administrator operations. Trust uses normalized lexical roots
(`C:\dev`, `Documents\Codex`, `.codex`, and the helper temp root), deliberately without
realpath/reparse censorship. Junction and symlink paths lexically beneath those roots are
accepted; direct outside-root and prefix-collision paths are refused. This is an elevated
code-execution primitive for a single-owner development machine. See
`elevated-dev-helper/README.md` for the full safety model.

## Safety Notes

- Review scripts before installing on a new machine.
- Do not store credentials, tokens, helper queue jobs, helper logs, or machine-specific generated state in this repo.
- Higher-priority Codex, project, OS, legal, and safety rules still apply.

## Tests

Double-click `Run-Tests.cmd`.

The behavioral tests in `tests/TEST-PLAN.md` must be run under the active Codex Desktop
configuration.
