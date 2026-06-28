# Changelog

All notable changes to the Codex Desktop Autonomy Kit. Dates are UTC.

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
