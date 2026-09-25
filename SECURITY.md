# Security Policy

## Supported Scope

This project supports modern macOS systems whose `/etc/pam.d/sudo` includes `/etc/pam.d/sudo_local`.

It does not support replacing `/etc/pam.d/sudo`, disabling password fallback, or loading PAM modules directly from user-owned package-manager paths.

## Security Invariants

The installer and documentation must preserve these properties:

- Never edit or replace `/etc/pam.d/sudo`.
- Write only `/etc/pam.d/sudo_local`.
- Do not use `/opt/homebrew/lib/pam/pam_reattach.so` or any Homebrew Cellar path in PAM configuration.
- Copy `pam_reattach.so` to `/usr/local/lib/pam/pam_reattach.so`.
- When building from source, verify the release tarball checksum before compiling.
- Stage source builds into a temporary directory and copy only `pam_reattach.so` into the root-owned PAM module path.
- Ensure `/usr/local`, `/usr/local/lib`, `/usr/local/lib/pam`, and the copied module are root-owned and not group/other writable.
- Ensure `/etc/pam.d/sudo_local` is root-owned and not group/other writable.
- Check parent directory ownership before any privileged write, not only after.
- Never remove `/usr/local/lib/pam/pam_reattach.so` while `sudo_local` references it. OpenPAM rejects the whole sudo policy if a listed module cannot be loaded, whatever its control flag.
- Use `ignore_ssh` unless remote biometric prompts are an explicit, documented non-default mode.
- Keep `pam_reattach` as `optional`.
- Keep `pam_tid` as `sufficient`.
- Preserve password fallback through the rest of Apple's sudo PAM stack.

## Reporting Vulnerabilities

Report suspected vulnerabilities privately through GitHub's "Report a vulnerability" button on the Security tab. Do not open a public issue for them.

## Reporting Other Issues

Open a GitHub issue with:

- macOS version
- `./scripts/audit.sh` output
- Whether Touch ID works in Terminal, tmux, and SSH
- Any changes made manually to `/etc/pam.d/sudo_local`

Do not include passwords, private keys, or full system logs.
