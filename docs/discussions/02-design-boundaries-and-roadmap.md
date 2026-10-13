# Design boundaries and roadmap

The kit is intentionally opinionated: it optimizes for an owner-controlled Windows
development machine where Codex Desktop should be able to inspect, edit, install, configure,
build, test, debug, retry, and clean up ordinary development work.

Current design boundaries:

- No-CLI normal path. If a user needs to install, update, check, test, refresh, or uninstall,
  there should be a double-click wrapper.
- Existing custom Codex configs are never wholesale-replaced. As of v2.0.0, setup reconciles
  only the kit's own autonomy keys in place (backing up first) and leaves everything else
  untouched; `-SkipReconcile` restores the old leave-entirely-alone behavior.
  `developer_instructions` is never injected on an existing config; the full profile stays a
  manual merge from the staged files.
- When setup does overwrite a kit-owned config, it records the exact backup path and hash;
  uninstall does not guess from unrelated `.bak-*` files.
- The elevated helper is powerful but structured. It accepts named development actions and
  writes logs/results; it is not meant to become a generic arbitrary-command admin broker.
- Uninstall turns the kit off for Codex Desktop but leaves general-purpose tools and helper
  files alone.
- Doctor is read-only and should explain state clearly enough for non-CLI use.

Near-term roadmap ideas:

- a packaged Windows installer around the current wrappers,
- a clearer first-run success screen,
- more Doctor checks for Pages/docs/version consistency,
- helper action additions driven by real local development failures,
- screenshots or short demo clips for the public landing page,
- optional signed releases once the public flow settles.

Questions for discussion:

- Which tasks still force a user back into command-line thinking?
- Which helper actions are worth adding without making the helper too broad?
- What should the installer explain before asking for UAC?
- What would make the uninstall story feel completely unsurprising?
