# Codex Desktop Autonomy Kit

Private personal kit for configuring Codex Desktop toward maximum practical software-development autonomy on Windows machines.

## Contents

- `GEN5-Codex-Desktop-Autonomous-Software-Development.md` - durable Codex prompt/instruction profile for autonomous development work.
- `elevated-dev-helper/` - reusable bounded elevated-helper pattern for Windows machines where Codex Desktop cannot launch its shell with an admin token.

## Intended Use

Use GEN5 as the persistent Codex instruction baseline for personal development machines. It authorizes Codex to inspect, edit, install, configure, build, test, debug, retry, verify, and clean up ordinary development work within higher-priority rules and real OS/app boundaries.

Use the elevated helper only when a machine needs a controlled way for non-admin Codex Desktop sessions to trigger supported elevated development infrastructure actions.

## Elevated Helper Setup

The helper still requires a one-time owner-approved Windows UAC step on each machine. See:

`elevated-dev-helper/README.md`

The helper is intentionally bounded. It supports named development actions and logs results; it is not an unrestricted admin command broker.

## Safety Notes

- Keep this repo private.
- Review scripts before installing on a new machine.
- Do not store credentials, tokens, helper queue jobs, helper logs, or machine-specific generated state in this repo.
- Higher-priority Codex, project, OS, legal, and safety rules still apply.
