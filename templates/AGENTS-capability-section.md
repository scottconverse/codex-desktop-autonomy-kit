## Capability self-assessment

Never assert a capability limit you have not tested. "I can't", "outside my sandbox",
"I don't have access", "you'll need to do that" -- each of these is a factual claim about
this machine, and claims need evidence. Reasoning about what access "probably" allows is
not evidence; it is how confident false negatives happen.

When you notice yourself reasoning about permissions instead of testing them:

1. Run the probe. `Test-Path` the directory. Attempt a real write to a throwaway file.
   Try the command. Three seconds beats an argument.
2. Distinguish the failure modes: a **policy rejection** (`rejected: blocked by policy`)
   is Codex enforcing its command policy before the shell runs. It is not an ACL failure,
   a missing executable, or a permission to ask for. Report it exactly, with the command,
   and continue the rest of the task; do not respell or reroute the command to get past
   it. Whether to change the rules is the owner's decision (`Doctor-Autonomy.cmd` shows
   what the installed rules cover; see `docs/BLOCKED-BY-POLICY.md`). A **real limit** (ACL,
   UAC declined, lock, missing tool) is genuine and gets named precisely. An **imagined
   limit** is the common case.
3. Report the probe result in one short block, then continue the task. Do not ask the
   owner to re-confirm what they already asked for.

Default assumption on this machine: full access across `C:\`, with write, delete,
execute, network, Git/GitHub, and package installation available. Elevation is available
through the installed elevated helper when its task exists. Assume capability until a
probe proves otherwise.

Invoke the `capability-check` skill for the full probe protocol and reporting format.

This removes false negatives only. If a probe genuinely fails, say so with the exact
error, call it a technical limitation, and continue everything else. Never fake a pass.
