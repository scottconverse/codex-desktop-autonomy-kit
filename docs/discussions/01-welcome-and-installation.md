# Welcome: what this kit is for

Codex Desktop Autonomy Kit is now public.

The goal is straightforward: make Codex Desktop more useful on a Windows development machine
without asking users to memorize setup commands. The normal path is clone or download,
double-click `Install-Autonomy.cmd`, approve Windows UAC only when the elevated helper needs
setup or refresh, then restart Codex Desktop.

What the kit currently provides:

- click-first install, doctor, uninstall, tests, and helper-refresh wrappers,
- persistent Codex developer instructions,
- safe handling for existing custom `~/.codex/config.toml`,
- exact config-backup ownership for safe uninstall,
- staged profile files and a versioned manifest under `~/.codex/autonomy-kit`,
- common development toolchain bootstrap with release-pinned remote scripts,
- optional scheduled-task elevated helper for structured admin development actions,
- read-only Doctor diagnostics,
- regression tests for install behavior and helper surface.

Good first discussion topics:

- install experiences on fresh Windows machines,
- which helper actions should be added next,
- how the docs can make the no-CLI path clearer,
- what should stay intentionally manual or owner-approved.

Please include your Windows version, Codex Desktop version, and the output summary from
`Doctor-Autonomy.cmd` when reporting install behavior.

For security reports, use the private-reporting guidance in [`SECURITY.md`](../../SECURITY.md)
before opening a public issue.
