# Codex Desktop Autonomy Kit

**Version 1.6.1 - Windows** - a click-first setup kit for configuring Codex Desktop toward
maximum practical software-development autonomy on Windows development machines. See
[CHANGELOG.md](CHANGELOG.md).

[Landing page](docs/index.html) | [User manual](docs/USER-MANUAL.md) | [Elevated helper details](elevated-dev-helper/README.md)

![Codex Desktop Autonomy Kit architecture](docs/assets/codex-autonomy-architecture.svg)

## What It Does

Codex Desktop Autonomy Kit turns a Windows Codex Desktop install into a more capable local
development collaborator. It stages persistent Codex instructions, configures the Codex
sandbox for full local development access, installs common user-scope tooling, and optionally
installs a bounded elevated helper for development tasks that need administrator rights.

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
- `elevated-dev-helper/` - reusable bounded elevated-helper pattern for Windows machines where Codex Desktop cannot launch its shell with an admin token.
- `tests/` - capability harness, behavioral test plan, and hardcoded-path regression guard.
- `skills/capability-check/` - shipped skill that makes an agent probe its own access instead of asserting limits it never tested.
- `templates/AGENTS-capability-section.md` - the marker-delimited capability rule Setup appends to your global `AGENTS.md`.

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

Use the elevated helper only when a machine needs a controlled way for non-admin Codex Desktop sessions to trigger supported elevated development infrastructure actions.

## Quick Start

From a clean Windows/Codex box, clone or download the kit, then double-click:

`Install-Autonomy.cmd`

Then restart Codex Desktop so PATH and config changes load.

### What setup will and will not do to your config

`Setup-Autonomy.ps1` creates `~/.codex/config.toml` only when it does not exist. If one exists,
it replaces it only when the file is provably kit-owned:

- **It matches the exact template the kit generates**, optionally differing only in the kit's
  own `# version = "..."` line.
- **You passed `-ForceConfig`** explicitly.

Anything else -- including a config that carries the kit marker but which you have edited
since -- is left byte-for-byte unchanged, and setup stages files under
`~/.codex/autonomy-kit/` for manual merge. A backup is taken before any overwrite that does
happen.

The kit does **not** use substring or "looks like a template" heuristics to decide ownership.
v1.6.1 fixed exactly that: an earlier version treated a config as kit-managed when it merely
contained the core heading and an `approval_policy = "never"` line, and could overwrite a
heavily customized config. A false positive here costs your entire configuration, so the test
is anchored and the real-world custom shapes are regression-tested.

Besides config, setup stages the instruction profiles under `~/.codex/autonomy-kit`, installs
the `capability-check` skill, and appends the capability rule to `~/.codex/AGENTS.md` (keeping
any content you already had there).

Status check: double-click `Doctor-Autonomy.cmd`. Doctor also reports whether the capability
rule and skill are installed.

If the elevated helper is stale, the installer offers to refresh it in the same flow. Approve
the Windows administrator prompt when you choose yes. The elevated installer window closes
after the helper install and self-test complete.

## Elevated Helper Setup

The helper still requires a one-time owner-approved Windows UAC step on each machine. See:

`elevated-dev-helper/README.md`

The helper is intentionally bounded. It supports named development actions and logs results; it is not an unrestricted admin command broker.

## Safety Notes

- Review scripts before installing on a new machine.
- Do not store credentials, tokens, helper queue jobs, helper logs, or machine-specific generated state in this repo.
- Higher-priority Codex, project, OS, legal, and safety rules still apply.

## Tests

Double-click `Run-Tests.cmd`.

The behavioral tests in `tests/TEST-PLAN.md` must be run under the active Codex Desktop
configuration.
