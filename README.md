# Codex Desktop Autonomy Kit

**Version 1.4.2 - Windows** - private personal kit for configuring Codex Desktop toward
maximum practical software-development autonomy on Windows machines. See
[CHANGELOG.md](CHANGELOG.md).

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
- `Uninstall-Autonomy.cmd` - double-click uninstall wrapper.
- `Refresh-ElevatedHelper.cmd` - double-click elevated-helper refresh wrapper.
- `Run-Tests.cmd` - double-click test runner wrapper.
- `CODEX-Desktop-Core.md` - compact standing instructions for everyday speed.
- `GEN5-Codex-Desktop-Autonomous-Software-Development.md` - full/depth Codex instruction
  profile for broad or high-blast-radius work.
- `config.autonomy.example.toml` - example Codex autonomy config for manual merge.
- `elevated-dev-helper/` - reusable bounded elevated-helper pattern for Windows machines where Codex Desktop cannot launch its shell with an admin token.
- `tests/` - capability harness, behavioral test plan, and hardcoded-path regression guard.

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

`Setup-Autonomy.ps1` creates `~/.codex/config.toml` only if it does not already exist, or
refreshes it only when it is clearly kit-managed. If you already have a custom config, it
leaves it unchanged and stages the kit files under `~/.codex/autonomy-kit` for manual merge.
Backups are created only before setup overwrites a kit-managed or forced config. This avoids
breaking Codex with duplicate TOML keys.

Status check: double-click `Doctor-Autonomy.cmd`.

If the elevated helper is stale, the installer offers to refresh it in the same flow. Approve
the Windows administrator prompt when you choose yes. The elevated installer window closes
after the helper install and self-test complete.

## Elevated Helper Setup

The helper still requires a one-time owner-approved Windows UAC step on each machine. See:

`elevated-dev-helper/README.md`

The helper is intentionally bounded. It supports named development actions and logs results; it is not an unrestricted admin command broker.

## Safety Notes

- Keep this repo private.
- Review scripts before installing on a new machine.
- Do not store credentials, tokens, helper queue jobs, helper logs, or machine-specific generated state in this repo.
- Higher-priority Codex, project, OS, legal, and safety rules still apply.

## Tests

Double-click `Run-Tests.cmd`.

The behavioral tests in `tests/TEST-PLAN.md` must be run under the active Codex Desktop
configuration.
