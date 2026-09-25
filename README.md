# macos-sudo-touchid

Enable Touch ID for `sudo` on macOS using Apple's `pam_tid.so`, with safer handling for terminal multiplexers through `pam_reattach`.

## Why This Exists

Modern macOS supports a local `sudo_local` PAM include file that survives system updates. A minimal Touch ID setup can be as small as enabling `pam_tid.so`, but that often fails from tmux or screen because Touch ID needs access to the user's GUI session.

This repository packages the safer version of that setup:

- `pam_reattach.so` reconnects the authentication flow to the user's GUI session.
- `pam_tid.so` performs Apple's Touch ID authentication.
- The active `pam_reattach.so` module is copied into a root-owned PAM module path.
- The PAM config never loads a module directly from Homebrew's user-writable prefix.

This project is intentionally conservative:

- It writes only `/etc/pam.d/sudo_local`.
- It does not replace Apple's `/etc/pam.d/sudo`.
- It copies `pam_reattach.so` into a root-owned path before PAM loads it.
- It does not point PAM at the user-owned Homebrew prefix.
- It uses `ignore_ssh` to avoid biometric prompts for SSH-originated sessions.

## Threat Model

This is a local convenience feature for personally administered Macs. It is not a hardening tool.

Touch ID for `sudo` changes the authentication experience from typing a password to approving a biometric prompt. `sudoers` policy still applies, and users still need permission to run `sudo`.

Avoid this on shared-admin, kiosk, lab, remote-admin, or high-assurance systems where every privilege elevation should require deliberate password entry.

## Requirements

- macOS with Touch ID configured.
- A user account that is already allowed to use `sudo`.
- Apple's `/etc/pam.d/sudo` must include `sudo_local`.
- Either Homebrew `pam-reattach`, or CMake plus Apple's command line tools to build `pam_reattach` from source.

## Install

Choose one `pam_reattach` install path.

Option A: use Homebrew as the source package:

```sh
brew install pam-reattach
```

Option B: build the upstream release from source and copy only the PAM module into the root-owned path:

```sh
./scripts/build-pam-reattach.sh
```

Then configure sudo:

```sh
./scripts/install.sh
```

Keep the current Terminal window open while testing. The installer backs up any existing `/etc/pam.d/sudo_local` file before changing it.

## What The Installer Does

The installer:

1. Verifies that `/etc/pam.d/sudo` includes `sudo_local`.
2. Refuses to overwrite unmanaged active PAM rules in `/etc/pam.d/sudo_local`.
3. Copies `pam_reattach.so` to `/usr/local/lib/pam/pam_reattach.so` if needed.
4. Enforces `root:wheel` ownership and non-writable permissions on the active PAM module path.
5. Writes a managed `/etc/pam.d/sudo_local`.
6. Validates `sudo` before exiting.

It does not edit `/etc/pam.d/sudo`.

## Audit

```sh
./scripts/audit.sh
```

The audit checks that:

- `/etc/pam.d/sudo` includes `sudo_local`.
- `/etc/pam.d/sudo_local` contains the expected `pam_reattach` and `pam_tid` lines.
- The active `pam_reattach.so` is root-owned and not writable by group or other.
- PAM is not loading the Homebrew-owned module path directly.

## Uninstall

```sh
./scripts/uninstall.sh
```

This disables only this project's `sudo_local` configuration if it matches the managed block. It does not remove Homebrew packages or delete `/usr/local/lib/pam/pam_reattach.so`.

After uninstalling, reinstalling from a non-interactive tool shell may fail because `sudo` will require a password and may not have a terminal. Reinstall from an interactive Terminal session:

```sh
cd /path/to/macos-sudo-touchid
./scripts/install.sh
```

## Development Checks

```sh
./scripts/check.sh
```

This runs shell syntax checks and the live audit. It does not run uninstall/reinstall, because uninstall intentionally disables Touch ID and changes how future `sudo` prompts behave.

## Security Review

See [docs/security-audit.md](docs/security-audit.md) for the public audit summary and release-readiness notes.

## Expected PAM Lines

```pam
auth       optional       /usr/local/lib/pam/pam_reattach.so ignore_ssh
auth       sufficient     pam_tid.so
```

`pam_reattach` is marked `optional` so a missing or broken module does not authenticate anyone. `pam_tid` is marked `sufficient` so successful Touch ID can satisfy sudo authentication, while failure falls through to the normal password path.
