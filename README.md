# Statically Linked [Dropbear SSH](https://github.com/mkj/dropbear) and sftp-server Binaries (built with Zig)

This repo publishes prebuilt **musl-linked static ELF binaries** of Dropbear,
built automatically from upstream [mkj/dropbear](https://github.com/mkj/dropbear)
using [Zig](https://ziglang.org/) for static musl compilation. Similarly for sftp-server.

These binaries should run on virtually any modern Linux distribution with no
external dependencies. Builds include **X11 forwarding support**.

## Motivation

I want to provide basic ssh server support for very general Docker containers,
with no installation requirements. E.g,. ssh for minimal SUSE or Ubuntu images, without having to run package managers.

## Contents

Each release provides these tarballs:

```
dropbear-x86_64-linux-musl.tar.xz
dropbear-aarch64-linux-musl.tar.xz
```

Extracting one yields:

```
dropbear-x86_64-linux-musl/
  dropbear
  dropbearkey
  dropbearconvert
  dbclient
  scp
```

To install, copy the two files somewhere on your `PATH`, e.g.:

```sh
sudo cp dropbear* /usr/local/bin/
```

In order to support sftp transparently, e.g., so sshfs works, extract the sftp-server binary and place it in `/usr/libexec/`:

```sh
sudo cp sftp-server /usr/libexec/sftp-server
```

## Basic Dropbear Tutorial

Generate a host key:

```sh
mkdir -p ~/dropbear-test
cd ~/dropbear-test
dropbearkey -t ed25519 -f key
```

Start the server in the foreground on port 2222:

```sh
dropbear -F -E -p 2222 -r key
```

From another terminal, connect:

```sh
ssh -p 2222 localhost
```

## Build Reproducibility

Binaries are built by [build.sh](./build.sh) and GitHub Actions workflows in
this repo. You can rerun the same process yourself to verify results.

## Notes

- Features: X11 forwarding enabled; PAM and zlib disabled; bundled libtom used.
- These builds are intended for lightweight use in containers or
  resource-constrained environments.
- **Security:** As with any SSH server, configure carefully (authorized_keys,
  permissions, etc.).
