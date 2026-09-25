# AGENTS.md

Guidance for coding agents working on this repository.

## Project Purpose

This repository provides a conservative macOS setup for Touch ID with `sudo`.

The project configures sudo through `/etc/pam.d/sudo_local`, uses Apple's `pam_tid.so`, and optionally uses `pam_reattach.so` so Touch ID works from terminal multiplexers such as tmux or screen.

This is a convenience feature, not a system hardening tool.

## Non-Negotiable Security Invariants

Do not weaken these without an explicit user request and a fresh security review:

- Never edit, replace, or generate `/etc/pam.d/sudo`.
- Write only `/etc/pam.d/sudo_local`.
- Never configure PAM to load `pam_reattach.so` from `/opt/homebrew`, Homebrew `Cellar`, or any user-writable package-manager path.
- The active PAM module path must be `/usr/local/lib/pam/pam_reattach.so`.
- `/usr/local`, `/usr/local/lib`, `/usr/local/lib/pam`, `/usr/local/lib/pam/pam_reattach.so`, and `/etc/pam.d/sudo_local` must be `root:wheel` and not group/other writable.
- Keep `pam_reattach` as `optional`.
- Keep `pam_tid` as `sufficient`.
- Keep `ignore_ssh` enabled by default.
- Preserve password fallback through Apple's normal sudo PAM stack.
- Source builds must verify the pinned upstream tarball checksum before compiling.
- Source builds must stage install output and copy only `pam_reattach.so` into the root-owned PAM module path.
- Check parent directory ownership before the first privileged write, not only afterward.
- Never remove or rename `/usr/local/lib/pam/pam_reattach.so` while `sudo_local` references it. OpenPAM rejects the whole sudo policy when a listed module cannot load, even an `optional` one.

## Scripts

- `scripts/build-pam-reattach.sh`: downloads, verifies, patches the upstream `ssh_env_vars` out-of-bounds read, builds, stages, and installs only `pam_reattach.so`.
- `scripts/install.sh`: installs the managed `sudo_local` configuration, re-authenticates with `sudo -k true`, and rolls back on failure.
- `scripts/uninstall.sh`: disables this project's managed configuration but does not delete `sudo_local`.
- `scripts/audit.sh`: audits the live machine state.
- `scripts/check.sh`: runs shell syntax checks and the live audit.

## Validation

Before declaring work complete, run:

```sh
./scripts/check.sh
```

For changes touching install, uninstall, PAM paths, ownership, permissions, or source build behavior, also review:

```sh
./scripts/audit.sh
```

Do not run uninstall/reinstall chains casually. `uninstall.sh` intentionally disables Touch ID for sudo, and reinstalling afterward may require an interactive Terminal password prompt.

## Documentation Hygiene

This repository is intended to be public.

Do not commit:

- Local usernames
- Hostnames
- E-mail addresses
- `/Users/...` paths
- Screenshots containing local identity
- Machine-specific logs
- Passwords, private keys, tokens, or full system logs
- Timestamped local backup filenames from `/etc/pam.d`

When adding audit notes, keep them generic and public-safe.

## Style

- Use POSIX `sh` for scripts unless there is a strong reason not to.
- Keep shell scripts defensive: quote variables, fail closed, reject symlinks, and validate ownership and permissions.
- Prefer exact, boring documentation over broad security claims.
- Do not describe this project as a bypass or a hardening control.
