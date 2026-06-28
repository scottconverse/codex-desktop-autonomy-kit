# Changelog

All notable changes to the Codex Desktop Autonomy Kit. Dates are UTC.

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
