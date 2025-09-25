#!/usr/bin/env bash
#set -euo pipefail
set -ev

# ---- Config ---------------------------------------------------------------
: "${OPENSSH_VERSION:=9.8p1}"     # OpenSSH portable version
: "${ZLIB_VERSION:=1.3.1}"        # zlib version to embed
: "${ZIG_VERSION:=0.15.1}"
: "${JOBS:=8}"

# TARGET values like: x86_64-linux-musl, aarch64-linux-musl
case "$(uname -m)" in
  x86_64)  TARGET="x86_64-linux-musl" ;;
  aarch64) TARGET="aarch64-linux-musl" ;;
  *) echo "Unsupported arch $(uname -m). Set TARGET explicitly."; exit 1 ;;
esac

workdir="$(pwd)"
builddir="$(mktemp -d)"
trap 'rm -rf "$builddir"' EXIT

# ---- Ensure zig available (reuse if already installed) --------------------
if ! command -v zig >/dev/null 2>&1; then
  zig_arch="$(uname -m)"
  zig_pkg="zig-${zig_arch}-linux-${ZIG_VERSION}.tar.xz"
  zig_url="https://ziglang.org/download/${ZIG_VERSION}/${zig_pkg}"
  echo "==> Downloading Zig ${ZIG_VERSION}"
  curl -fsSL "$zig_url" -o "${builddir}/${zig_pkg}"
  tar -C "$builddir" -xJf "${builddir}/${zig_pkg}"
  zig_root="$(tar -tf "${builddir}/${zig_pkg}" | head -1 | cut -d/ -f1)"
  export PATH="${builddir}/${zig_root}:$PATH"
fi
zig version

# ---- Build a musl-target static zlib --------------------------------------
echo "==> Building zlib ${ZLIB_VERSION} for ${TARGET} (static, musl)"
zlib_tar="zlib-${ZLIB_VERSION}.tar.gz"
zlib_url="https://zlib.net/${zlib_tar}"
curl -fsSL "$zlib_url" -o "${builddir}/${zlib_tar}"
tar -C "$builddir" -xzf "${builddir}/${zlib_tar}"
cd "${builddir}/zlib-${ZLIB_VERSION}"

# zlib has its own configure script
export CC="zig cc -target ${TARGET}"
export CFLAGS="-O2 -fno-pie -s"
export LDFLAGS="-static -no-pie"
# Use a private prefix that we'll point OpenSSH to
zlib_prefix="${builddir}/sysroot-zlib"
./configure --static --prefix="${zlib_prefix}"
make -j "${JOBS}"
make install

# Quick sanity
file "${zlib_prefix}/lib/libz.a" || true

# ---- Fetch & configure OpenSSH --------------------------------------------
echo "==> Downloading OpenSSH portable ${OPENSSH_VERSION}"
cd "${builddir}"
oss_tar="openssh-${OPENSSH_VERSION}.tar.gz"
oss_url="https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/${oss_tar}"
curl -fsSL "$oss_url" -o "${oss_tar}"
tar -xzf "${oss_tar}"
cd "openssh-${OPENSSH_VERSION}"

# Toolchain for musl
export CC="zig cc -target ${TARGET}"
export CFLAGS="-Os -fno-pie -s -I${zlib_prefix}/include"
export LDFLAGS="-static -no-pie -L${zlib_prefix}/lib"

# We only need headers/tests to pass; we won't link ssh/sshd
# Point configure to our musl zlib and keep other features off
./configure \
  --with-zlib="${zlib_prefix}" \
  --without-openssl \
  --without-pam \
  --without-kerberos5 \
  --without-selinux \
  --without-bsd-auth \
  --without-libedit \
  --without-ldns \
  --without-security-key-bsd \
  --disable-strip

echo "==> Building sftp-server (static, musl, with our zlib)"
make -j "${JOBS}" sftp-server

file sftp-server || true
# Expect: ELF ... statically linked ... (and typically "musl")

# ---- Stage and package (flat layout) --------------------------------------
stage="${builddir}/stage/sftp-server-${TARGET}"
mkdir -p "${stage}"
install -m 0755 sftp-server "${stage}/sftp-server"

cd "${builddir}/stage"
out="${workdir}/sftp-server-${TARGET}.tar.xz"
tar -cJf "${out}" "sftp-server-${TARGET}"
sha256sum "${out}" | tee "${out}.SHA256"

echo "==> Done: ${out}"
echo "Extracts to: sftp-server-${TARGET}/sftp-server"