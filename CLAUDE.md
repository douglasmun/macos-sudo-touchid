# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

The security invariants, script list, and documentation hygiene rules live in AGENTS.md (imported above) and apply in full. This file adds only what AGENTS.md does not cover.

## Commands

```sh
./scripts/check.sh          # sh -n on every scripts/*.sh, then the live audit
./scripts/audit.sh          # live machine audit only; PASS/FAIL per check, nonzero exit on any FAIL
sh -n scripts/install.sh    # syntax-check a single script
```

There is no unit test suite (`test/` and `assets/` are empty placeholders). `check.sh` and `audit.sh` inspect the real `/etc/pam.d` and `/usr/local/lib/pam`, so they fail on a machine where the managed config is not installed. That is expected, not a script bug.

`install.sh`, `uninstall.sh`, and `build-pam-reattach.sh` call `sudo` and modify system state. Do not run them unless the user asks. From a non-TTY tool shell, `pam_tid` cannot fire; if the user does ask, wrap in a pty: `script -q /dev/null /bin/sh -c 'sudo -v && ./scripts/install.sh'`.

## How the scripts fit together

- **Shared contract, duplicated by hand.** There is no shared library. Each script hardcodes its own copies of the paths (`/etc/pam.d/sudo_local`, `/usr/local/lib/pam/pam_reattach.so`). `install.sh` and `audit.sh` both hardcode the two expected PAM lines, column spacing included (`audit.sh` matches them with `grep -F`). `install.sh` and `uninstall.sh` both define the managed marker `# managed by macos-sudo-touchid`. A change to any of these must be made in every script that uses it, plus the "Expected PAM Lines" section of README.md.
- **Managed marker is the ownership signal.** `install.sh` overwrites `sudo_local` only if it carries the marker, is empty or comments-only, or already contains exactly the two expected active lines; anything else is refused. `uninstall.sh` refuses any file without the marker. The uninstall output deliberately omits the marker and leaves `pam_tid` commented out.
- **Module sourcing order in `install.sh`:** prefer an existing `/usr/local/lib/pam/pam_reattach.so` (from `build-pam-reattach.sh` or an earlier install), then fall back to `brew --prefix pam-reattach`. In both cases the module is copied into the root-owned path and PAM loads it from there, never from the Homebrew path.
- **Ownership checks after writes.** `assert_root_safe_path` re-checks `/usr/local`, `/usr/local/lib`, the PAM dir, the module, and `sudo_local` after installation (root:wheel, no symlink, no group/other write bit). New privileged writes should follow the same install-then-assert pattern using absolute binaries (`/usr/bin/install`, `/bin/cp`, `/usr/sbin/chown`).
- **Source build pin.** `build-pam-reattach.sh` pins `VERSION` and `TARBALL_SHA256` together. Bumping the version means updating both, plus `docs/pam-reattach-source-build.md`.
- Backups are written next to the target as `sudo_local.backup.<timestamp>` (install) and `sudo_local.removed.<timestamp>` (uninstall). Never commit those filenames or their contents.

## Docs to keep in sync

When behavior changes, update `README.md`, `docs/security-audit.md`, and `docs/public-release-checklist.md` along with the scripts.
