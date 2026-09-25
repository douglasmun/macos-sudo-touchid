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
- `/usr/local` and `/usr/local/lib` must be `root:wheel` and not group/other writable. This is the default on Apple Silicon. On Intel Macs, Homebrew usually owns `/usr/local/lib`, and the scripts refuse to run.
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
2. Verifies that `/etc/pam.d`, `/usr/local`, `/usr/local/lib`, and any existing `/usr/local/lib/pam` are `root:wheel`, not symlinks, and not group/other writable, before any privileged write.
3. Refuses to overwrite unmanaged active PAM rules in `/etc/pam.d/sudo_local`.
4. Copies `pam_reattach.so` to `/usr/local/lib/pam/pam_reattach.so` if it is not already there. An existing file at that path is reused only if it is already root-owned and safe.
5. Writes a managed `/etc/pam.d/sudo_local`, backing up any existing file next to it.
6. Re-authenticates once through the new PAM stack with `sudo -k true`. If that fails, it restores the previous `sudo_local` using the still-cached sudo credentials.

It does not edit `/etc/pam.d/sudo`.

## Updating pam_reattach

The installer reuses the module already at `/usr/local/lib/pam/pam_reattach.so`, so upgrading Homebrew's `pam-reattach` does not change what PAM loads. To pick up a new build, run `./scripts/build-pam-reattach.sh` again, or replace the module from Homebrew:

```sh
sudo /usr/bin/install -o root -g wheel -m 0444 "$(brew --prefix pam-reattach)/lib/pam/pam_reattach.so" /usr/local/lib/pam/pam_reattach.so
./scripts/audit.sh
```

Uninstalling Homebrew's `pam-reattach` does not affect sudo, because PAM loads the root-owned copy.

## Upstream Patch

`pam_reattach` v1.3 has an out-of-bounds read in its `ignore_ssh` check: it loops `sizeof(ssh_env_vars)` times (the array's size in bytes) over a three-element array. `scripts/build-pam-reattach.sh` patches this after verifying the tarball checksum. The Homebrew bottle is built from unpatched upstream source. Prefer the source build if this matters to you.

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

This runs shell syntax checks and the live audit. The audit reads the real `/etc/pam.d` and `/usr/local/lib/pam`, so it fails on a machine where this configuration is not installed. It does not run uninstall/reinstall, because uninstall intentionally disables Touch ID and changes how future `sudo` prompts behave.

## Recovery

Do not delete `/usr/local/lib/pam/pam_reattach.so` while `sudo_local` references it. OpenPAM rejects the whole sudo policy if it cannot load a listed module, even an `optional` one. Every `sudo` call then fails, including password authentication.

If that happens, restore Apple's comment-only template through the macOS administrator dialog. It uses Authorization Services, not the sudo PAM stack:

```sh
osascript -e 'do shell script "/bin/cp /etc/pam.d/sudo_local.template /etc/pam.d/sudo_local" with administrator privileges'
```

Then run `./scripts/install.sh` again if you want Touch ID back.

## Security Review

See [docs/security-audit.md](docs/security-audit.md) for the public audit summary and release-readiness notes.

## Expected PAM Lines

```pam
auth       optional       /usr/local/lib/pam/pam_reattach.so ignore_ssh
auth       sufficient     pam_tid.so
```

`pam_reattach` is marked `optional` because it only prepares the GUI session for `pam_tid`. It never authenticates anyone, and a runtime failure falls through. The module file must exist, though; see [Recovery](#recovery). `pam_tid` is marked `sufficient` so successful Touch ID can satisfy sudo authentication, while failure falls through to the normal password path.

`ignore_ssh` skips reattaching when `SSH_CLIENT`, `SSH_CONNECTION`, or `SSH_TTY` is set in the sudo process's environment. A tmux or screen session started locally and later attached over SSH keeps its original environment in existing panes, because tmux's `update-environment` only affects panes created after the attach. sudo from such a pane can still show a Touch ID prompt on the Mac's local display, which only someone at the Mac can approve.
