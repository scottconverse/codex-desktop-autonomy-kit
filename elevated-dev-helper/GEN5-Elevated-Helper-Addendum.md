# GEN5 Addendum - Bounded Elevated Development Helper

Use this addendum with GEN5 on machines where Codex Desktop cannot reliably launch with an elevated/admin shell token.

## Purpose

Codex is authorized to use a local elevated development helper when one has been installed by the machine owner. The helper exists to bridge Windows UAC/admin-token limitations for ordinary, reversible software-development infrastructure tasks.

## Helper Model

The helper is a Windows Scheduled Task configured to run a trusted local PowerShell script with highest privileges. Codex Desktop remains a normal-user process, but can queue structured helper requests and trigger the task. The elevated helper executes only supported development actions, writes structured logs, and exits.

## Authorized Helper Uses

Codex may use the helper for normal development infrastructure, including:

- Installing trusted development tools through package managers or local installers.
- Configuring SDKs, runtimes, browser drivers, local databases, Docker, WSL, VM prerequisites, and emulator prerequisites.
- Starting, stopping, or restarting named local development services.
- Creating or updating development-only scheduled tasks from trusted local scripts.
- Opening local development firewall rules when the rule is scoped to localhost, private networks, or a clearly development-only port.
- Running environment checks that require admin visibility.

## Required Helper Behavior

When admin capability is needed:

1. Prefer non-admin, project-local, user-scoped, portable, container-scoped, or VM-scoped options when they complete the task correctly.
2. If admin is actually required, create a structured helper request for a supported action.
3. Trigger the helper task if it is installed.
4. Read the helper result log.
5. Continue all non-admin work while any helper request is pending or blocked.

## Boundaries

The helper must not be treated as permission to perform destructive, credential-sensitive, security-sensitive, internet-exposed, or hard-to-reverse actions silently.

The helper should refuse unrestricted arbitrary commands. It should execute named, supported development actions with structured parameters, log every action, and preserve a review trail.

## Portability

This addendum is reusable on other personal development machines. On each machine, the helper still requires a one-time owner-approved elevated setup step because Windows UAC and OS policy cannot be bypassed by prompt text.
