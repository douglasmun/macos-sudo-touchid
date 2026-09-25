# Build `pam_reattach` From Source

Use this path when you do not want to depend on Homebrew's installed copy, or when you want the repository to document the full download, compile, and root-owned install flow.

The build script downloads the upstream `pam_reattach` release tarball, verifies its SHA-256, builds it with CMake, installs into a temporary staging directory, then copies only `pam_reattach.so` to:

```text
/usr/local/lib/pam/pam_reattach.so
```

It deliberately does not point PAM at the Homebrew prefix or the build directory.

## Prerequisites

Install Apple's command line tools and CMake:

```sh
xcode-select --install
brew install cmake
```

## Build And Install The PAM Module

```sh
./scripts/build-pam-reattach.sh
```

The script currently pins:

- Upstream: `https://github.com/fabianishere/pam_reattach`
- Version: `1.3`
- Release tarball SHA-256: `b1b735fa7832350a23457f7d36feb6ec939e5e1de987b456b6c28f5738216570`

After the module is installed, configure sudo:

```sh
./scripts/install.sh
```

Then audit:

```sh
./scripts/audit.sh
```

## Why Stage First?

Running `cmake --install` directly against `/usr/local` can install extra files and makes rollback harder. This project stages the build into a temporary directory and copies only the PAM module into the root-owned PAM module directory.
