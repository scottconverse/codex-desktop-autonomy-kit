# Changelog

All notable changes to the Codex Desktop Autonomy Kit. Dates are UTC.

Verification note: this repository has no CI workflow. Test and smoke-check results
recorded in release notes are produced by running the shipped scripts manually, not by
an automated service.

## v1.6.1 - 2026-09-21

### Fixed
- **Data loss: the installer could replace a customized `config.toml`.** `Setup-Autonomy.ps1`
  classified a config as kit-managed when it merely *contained* the Autonomy Core heading and
  an `approval_policy = "never"` line anywhere in the file. Any customized config matching both
  -- for example, one using `approval_policy = "never"` with the core profile as
  `developer_instructions` -- was treated as a replaceable template and overwritten in full,
  destroying model selection, appearance settings, plugins, hooks, and project trust entries.
  The test suite did not catch it because the custom-config case used a single-line file that
  could not trigger the heuristic.

  The ownership test is now anchored: a config is replaced only when it matches the generated
  template exactly (optionally differing only in the kit's own version comment line), or when
  `-ForceConfig` is passed explicitly. A config carrying the kit marker but edited since
  installation is now preserved and reported, rather than silently replaced.

  Real-world custom shapes are now regression-tested: `never` plus the core heading, `never`
  plus plugin tables, marker present but not first, kit template with user additions, and a
  fully customized config. Each must survive byte-for-byte. The mutation that reintroduced the
  original heuristic turns four checks red.

- `Uninstall-Autonomy.ps1` now requires both the begin and end capability markers in
  `AGENTS.md`. A lone begin marker previously risked a partial excision; it is now left
  untouched and reported for manual review.

### Notes
- If you installed v1.5.0 or v1.6.0 on a machine with a customized `config.toml`, check
  `~/.codex/config.toml.bak-*` for a pre-install backup. The installer always backed up before
  overwriting, so the prior configuration should be recoverable from the most recent backup.

## v1.6.0 - 2026-09-21

### Added
- `capability-check` skill: forces an empirical probe of the agent's own access instead of
  asserting limits it never tested. Ships in `skills/capability-check/` and installs to
  `~/.codex/skills/capability-check/`.
- Capability self-assessment section in `CODEX-Desktop-Core.md`, so the rule travels with
  the profile.
- `templates/AGENTS-capability-section.md` and a guarded `AGENTS.md` writer in
  `Setup-Autonomy.ps1`. The rule is appended inside begin/end markers, only if absent,
  with a backup taken first. Owner-written content is never rewritten.
- Doctor now reports whether the AGENTS.md rule and the skill are installed.
- Uninstall removes only the kit-authored AGENTS.md block, keeping owner content, and
  removes the installed skill.

### Changed
- Helper root is resolved from `~/.codex/autonomy-kit/helper-root.json` rather than
  assuming `C:\dev`. Default behavior is unchanged; this fixes a latent mismatch when a
  custom `-InstallRoot` is used.
- Install steps warn and continue instead of aborting before config staging.

### Fixed
- Added root MIT `LICENSE` (previously absent).

### Notes
- Repository has no CI workflow; test and smoke-check results are produced by running the
  shipped scripts manually.

## v1.5.0 - 2026-06-28

### Added
- Public-facing landing page under `docs/index.html`.
- Full user manual under `docs/USER-MANUAL.md`.
- Professional architecture graphic shared by the README, user manual, and landing page.
- Seed GitHub Discussion posts under `docs/discussions/`.

### Changed
- README now describes the project as a public click-first Windows kit instead of a private
  personal repo.
- Setup manifest version now writes the current kit version.

## v1.4.2 - 2026-06-28

### Fixed
- The elevated helper installer no longer leaves an Administrator PowerShell window open
  after a successful click-driven refresh.
- The helper admin launcher now waits for the elevated installer and propagates its exit
  code back to the calling installer.
- Helper install self-test now fails the installer if it does not complete or does not prove
  administrator execution.

## v1.4.1 - 2026-06-28

### Changed
- `Install-Autonomy.cmd` is now the one-stop installer/updater: it runs setup, runs Doctor,
  detects a stale elevated helper, and offers to refresh it from the same double-click flow.

## v1.4.0 - 2026-06-28

### Added
- Double-click root launchers:
  - `Install-Autonomy.cmd`
  - `Doctor-Autonomy.cmd`
  - `Uninstall-Autonomy.cmd`
  - `Refresh-ElevatedHelper.cmd`
  - `Run-Tests.cmd`
- README quick start now presents the no-CLI path first.

## v1.3.1 - 2026-06-28

### Fixed
- Repeat `Setup-Autonomy.ps1 -ConfigOnly` runs on an already-current kit-managed
  `config.toml` no longer create backups due only to encoding or line-ending differences.
- `tests/Test-InstallSurface.ps1` now proves repeat kit-managed setup has no backup churn.

## v1.3.0 - 2026-06-28

### Added
- `Setup-Autonomy.ps1 -ConfigOnly -CodexRoot <path>` for isolated first-run config
  verification without installing tools or touching the real `~/.codex`.
- `Setup-Autonomy.ps1 -RefreshHelper` to launch the elevated helper installer when Doctor or
  setup detects an installed helper script that differs from the repo copy.
- Regression coverage that runs setup against a temporary Codex root and proves kit-managed
  config, staged profiles, manifest creation, and custom-config preservation.

### Changed
- Setup now creates `config.toml` backups only before an actual overwrite. Custom configs left
  unchanged no longer produce backup churn on every re-run.

## v1.2.0 - 2026-06-28

### Added
- Kit-owned vs customized config handling. Setup now writes a marker on generated
  `config.toml`, refreshes only kit-managed/old-kit configs by default, and leaves custom
  configs staged for manual merge.
- Staged profile manifest with SHA-256 hashes.
- Richer Doctor checks for staged profile freshness, possible duplicate top-level TOML keys,
  helper queue/done/failed/log folder writability, and installed-helper parity.
- `tests/Test-InstallSurface.ps1` for setup/doctor/uninstall/helper surface regression checks.
- `tests/Test-ScriptSyntax.ps1` for PowerShell parser checks across shipped scripts.

### Changed
- `Uninstall-Autonomy.ps1` now removes `config.toml` only when it is clearly kit-managed and
  no backup exists; otherwise it restores backups or leaves custom config untouched.
- Setup reports stale installed helper scripts instead of silently treating an existing helper
  task as fully current.

## v1.1.0 - 2026-06-28

### Added
- `Setup-Autonomy.ps1` for fresh-machine bootstrap of common no-admin development tooling,
  staged Codex autonomy profiles, first-run config creation, and optional elevated-helper
  installation.
- `Doctor-Autonomy.ps1` read-only dashboard for toolchain, Codex config, profile staging,
  and elevated-helper state.
- `Uninstall-Autonomy.ps1` to reverse the kit config layer and optionally unregister the
  elevated helper.
- `CODEX-Desktop-Core.md`, a compact daily instruction profile with a depth rule pointing to
  the full GEN5 profile.
- `config.autonomy.example.toml` for manual config merges.
- `tests/` capability harness, behavioral test plan, and hardcoded-path regression guard.

### Fixed
- Hardened the elevated helper with portable trusted roots, PowerShell 5.1-compatible process
  launching, async stdout/stderr draining, bounded waits, real `winget.exe` resolution inside
  elevated scheduled tasks, and silent/noninteractive winget flags.

## v1.0.0 - 2026-06-28

### Added
- Initial Codex Desktop autonomy profile and bounded elevated development helper.
