# Codex Desktop Autonomy Kit

**Version 1.3.1 - Windows** - private personal kit for configuring Codex Desktop toward
maximum practical software-development autonomy on Windows machines. See
[CHANGELOG.md](CHANGELOG.md).

## Contents

- `Setup-Autonomy.ps1` - one-command fresh-machine bootstrap. Installs common user-scope
  development tooling, stages Codex autonomy profiles, creates first-run config when no
  config exists, and triggers the elevated helper installer if needed.
- `Doctor-Autonomy.ps1` - read-only status dashboard for toolchain, config, staged profile
  freshness, helper task/folder state, and installed-helper parity.
- `Uninstall-Autonomy.ps1` - reverses the config layer and optionally unregisters the
  elevated helper. Leaves the general-purpose toolchain alone.
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

From a clean Windows/Codex box, clone the kit and run the bootstrap from a non-admin shell:

```powershell
git clone https://github.com/scottconverse/codex-desktop-autonomy-kit.git
cd codex-desktop-autonomy-kit
powershell -NoProfile -ExecutionPolicy Bypass -File .\Setup-Autonomy.ps1
```

Then restart Codex Desktop so PATH and config changes load.

`Setup-Autonomy.ps1` creates `~/.codex/config.toml` only if it does not already exist, or
refreshes it only when it is clearly kit-managed. If you already have a custom config, it
leaves it unchanged and stages the kit files under `~/.codex/autonomy-kit` for manual merge.
Backups are created only before setup overwrites a kit-managed or forced config. This avoids
breaking Codex with duplicate TOML keys.

For non-destructive config-only verification, run setup against an isolated root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Setup-Autonomy.ps1 -ConfigOnly -CodexRoot "$env:TEMP\codex-kit-check"
```

If `Doctor-Autonomy.ps1` reports the installed elevated helper is stale, refresh it with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Setup-Autonomy.ps1 -RefreshHelper
```

Status check:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Doctor-Autonomy.ps1
```

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

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-NoHardcodedPaths.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-InstallSurface.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ScriptSyntax.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-AutonomyKit.ps1
```

The behavioral tests in `tests/TEST-PLAN.md` must be run under the active Codex Desktop
configuration.
