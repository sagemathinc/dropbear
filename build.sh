#!/usr/bin/env bash
set -ev

# ---- Config ----------------------------------------------------------------
: "${DROPBEAR_VERSION:=2025.88}"   # Dropbear release to build
: "${ZIG_VERSION:=0.15.1}"         # Zig to use for musl cross static
: "${JOBS:=8}"                     # parallel make

# TARGET may be provided by CI matrix (e.g., x86_64-linux-musl, aarch64-linux-musl
if [[ -z "${TARGET:-}" ]]; then
  case "$(uname -m)" in
    x86_64)  TARGET="x86_64-linux-musl" ;;
    aarch64) TARGET="aarch64-linux-musl" ;;
    *) echo "Unsupported arch $(uname -m). Set TARGET explicitly."; exit 1 ;;
  esac
fi

workdir="$(pwd)"
builddir="$(mktemp -d)"
trap 'rm -rf "$builddir"' EXIT

zig_pkg_arch=`uname -m`
zig_pkg="zig-${zig_pkg_arch}-linux-${ZIG_VERSION}.tar.xz"
zig_url="https://ziglang.org/download/${ZIG_VERSION}/${zig_pkg}"

echo "Downloading Zig ${ZIG_VERSION} for ${zig_pkg_arch}..."
curl -fsSL "$zig_url" -o "${builddir}/${zig_pkg}"
echo "Extracting Zig to $builddir..."
tar -C "$builddir" -xJf "${builddir}/${zig_pkg}"
echo "Extracted zig"

zig_root="$(tar -tf "${builddir}/${zig_pkg}" | head -1 | cut -d/ -f1)"
ZIG_BIN="${builddir}/${zig_root}/zig"
export PATH="${builddir}/${zig_root}:$PATH"
echo "Using Zig at: ${ZIG_BIN}"
"${ZIG_BIN}" version

# --- Get Dropbear -----------------------------------------------------------
dropbear_tar="dropbear-${DROPBEAR_VERSION}.tar.bz2"
dropbear_url="https://matt.ucc.asn.au/dropbear/releases/${dropbear_tar}"

echo "Downloading Dropbear ${DROPBEAR_VERSION}..."
curl -fsSL "$dropbear_url" -o "${builddir}/${dropbear_tar}"
echo "Extracting Dropbear..."
tar -C "$builddir" -xjf "${builddir}/${dropbear_tar}"
cd "${builddir}/dropbear-${DROPBEAR_VERSION}"

# --- Build (static, musl) ---------------------------------------------------
echo "Cleaning previous build (if any)…"
make clean || true

echo "Configuring for ${TARGET}…"
CC="${ZIG_BIN} cc -target ${TARGET}" \
CFLAGS="-Os -fno-pie" \
LDFLAGS="-static -no-pie" \
CPPFLAGS="-DDROPBEAR_X11FWD" \
./configure \
  --host="${TARGET}" \
  --disable-pam \
  --disable-zlib \
  --enable-bundled-libtom \
  --enable-static

echo "Building dropbear…"
make -j "${JOBS}" PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" STATIC=1

# --- Package ----------------------------------------------------------------
[[ -x ./dropbear ]] || { echo "Build failed: dropbear missing"; exit 1; }
strip ./drop* dbclient scp || true

# Stage files (with symlinks) inside dropbear-${TARGET}/
stage_dir="${builddir}/stage/dropbear-${TARGET}"
mkdir -p "${stage_dir}"
cp ./dropbear* dbclient scp "${stage_dir}/"

# Produce dropbear-${TARGET}.tar.xz in the original working dir
out_tar="${workdir}/dropbear-${TARGET}.tar.xz"
echo "Creating ${out_tar}…"
tar -C "${builddir}/stage" -cJf "${out_tar}" "dropbear-${TARGET}"

# SHA256 for convenience
echo "SHA256: "
sha256sum "${out_tar}" | tee "${out_tar}.SHA256"

echo "Done: ${out_tar}"
