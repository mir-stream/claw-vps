#!/usr/bin/env bash
# build-kernel.sh — build the Firecracker guest kernel (invoked as: clawvps setup kernel)
# The Firecracker CI kernels lack TUN/nf_tables, which breaks Tailscale and
# iptables inside guests. This builds the Amazon Linux microVM kernel from the CI
# config with those enabled.
# Works on both aarch64 and x86_64 (auto-detected).
# Output: installed to /var/lib/vms/kernel-claw (plus a copy in ~/fc/kernel-claw).
set -euo pipefail

KVER="6.1.128"
# Build Firecracker's own (Amazon Linux microVM) kernel tree, NOT a vanilla
# kernel.org build. On x86_64, Firecracker describes its devices via ACPI, and a
# vanilla kernel fails to parse Firecracker's ACPI tables ("ACPI: Unable to load
# the System Description Tables" -> virtio-blk probe -EINVAL -> "Unable to mount
# root fs"). The AL microvm tree carries the patches that make this work; vanilla
# is explicitly unsupported by Firecracker's kernel policy. (aarch64 uses FDT and
# tolerated vanilla, so this only ever broke x86_64 guests.)
AMZN_TAG="microvm-kernel-${KVER}-3.201.amzn2023"
SRCDIR="linux-${AMZN_TAG}"
ARCH="$(uname -m)"        # aarch64 | x86_64
WORKDIR="${HOME}/fc/kernel-build"
OUT="${HOME}/fc/kernel-claw"
CONFIG_URL="https://s3.amazonaws.com/spec.ccfc.min/firecracker-ci/v1.12/${ARCH}/vmlinux-${KVER}.config"

echo "==> installing build dependencies"
sudo apt-get update -qq
sudo apt-get install -y -qq build-essential flex bison libssl-dev libelf-dev bc wget

mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

echo "==> fetching Amazon Linux microVM kernel source (${AMZN_TAG})"
if [ ! -d "${SRCDIR}" ]; then
  wget -q -O "${AMZN_TAG}.tar.gz" \
    "https://github.com/amazonlinux/linux/archive/refs/tags/${AMZN_TAG}.tar.gz"
  tar xf "${AMZN_TAG}.tar.gz"
fi

echo "==> fetching firecracker CI config (${ARCH})"
wget -q -O ci.config "${CONFIG_URL}"

cd "${SRCDIR}"
# Sanity: confirm the AL tag really carries the kernel version we pin, so a future
# Amazon Linux tag revision that bumps the base version can't slip through silently.
treever="$(make -s kernelversion 2>/dev/null)"
[ "${treever}" = "${KVER}" ] || { echo "ERROR: kernel tree is ${treever:-unknown}, expected ${KVER}" >&2; exit 1; }
cp ../ci.config .config

echo "==> enabling TUN / netfilter / nftables / conntrack / NAT / IPv6 / policy routing"
# Comprehensive set verified against Tailscale's iptables_runner.go: makes
# kernel-mode tailscale and standard iptables fully functional in guests.
./scripts/config \
  --enable CONFIG_TUN \
  --enable CONFIG_IPV6 \
  --enable CONFIG_IP_ADVANCED_ROUTER \
  --enable CONFIG_IP_MULTIPLE_TABLES \
  --enable CONFIG_IPV6_MULTIPLE_TABLES \
  --enable CONFIG_FIB_RULES \
  --enable CONFIG_NETFILTER \
  --enable CONFIG_NETFILTER_ADVANCED \
  --enable CONFIG_NF_CONNTRACK \
  --enable CONFIG_NF_CONNTRACK_MARK \
  --enable CONFIG_NF_NAT \
  --enable CONFIG_NF_DEFRAG_IPV4 \
  --enable CONFIG_NF_DEFRAG_IPV6 \
  --enable CONFIG_NF_TABLES \
  --enable CONFIG_NF_TABLES_INET \
  --enable CONFIG_NF_TABLES_IPV4 \
  --enable CONFIG_NF_TABLES_IPV6 \
  --enable CONFIG_NFT_CT \
  --enable CONFIG_NFT_NAT \
  --enable CONFIG_NFT_MASQ \
  --enable CONFIG_NFT_REDIR \
  --enable CONFIG_NFT_COMPAT \
  --enable CONFIG_NFT_LIMIT \
  --enable CONFIG_NFT_LOG \
  --enable CONFIG_NFT_REJECT \
  --enable CONFIG_NFT_REJECT_INET \
  --enable CONFIG_NETFILTER_XTABLES \
  --enable CONFIG_NETFILTER_XT_MARK \
  --enable CONFIG_NETFILTER_XT_CONNMARK \
  --enable CONFIG_NETFILTER_XT_NAT \
  --enable CONFIG_NETFILTER_XT_TARGET_MASQUERADE \
  --enable CONFIG_NETFILTER_XT_TARGET_MARK \
  --enable CONFIG_NETFILTER_XT_TARGET_CONNMARK \
  --enable CONFIG_NETFILTER_XT_TARGET_REDIRECT \
  --enable CONFIG_NETFILTER_XT_TARGET_LOG \
  --enable CONFIG_NETFILTER_XT_TARGET_TCPMSS \
  --enable CONFIG_NETFILTER_XT_MATCH_CONNTRACK \
  --enable CONFIG_NETFILTER_XT_MATCH_STATE \
  --enable CONFIG_NETFILTER_XT_MATCH_CONNMARK \
  --enable CONFIG_NETFILTER_XT_MATCH_MARK \
  --enable CONFIG_NETFILTER_XT_MATCH_COMMENT \
  --enable CONFIG_NETFILTER_XT_MATCH_ADDRTYPE \
  --enable CONFIG_NETFILTER_XT_MATCH_MULTIPORT \
  --enable CONFIG_NETFILTER_XT_MATCH_LIMIT \
  --enable CONFIG_NETFILTER_XT_MATCH_IPRANGE \
  --enable CONFIG_IP_NF_IPTABLES \
  --enable CONFIG_IP_NF_FILTER \
  --enable CONFIG_IP_NF_NAT \
  --enable CONFIG_IP_NF_MANGLE \
  --enable CONFIG_IP_NF_RAW \
  --enable CONFIG_IP_NF_TARGET_MASQUERADE \
  --enable CONFIG_IP_NF_TARGET_REJECT \
  --enable CONFIG_IP_NF_TARGET_REDIRECT \
  --enable CONFIG_IP6_NF_IPTABLES \
  --enable CONFIG_IP6_NF_FILTER \
  --enable CONFIG_IP6_NF_MANGLE \
  --enable CONFIG_IP6_NF_RAW \
  --enable CONFIG_IP6_NF_NAT \
  --enable CONFIG_IP6_NF_TARGET_REJECT \
  --enable CONFIG_IP6_NF_TARGET_MASQUERADE

echo "==> resolving config dependencies (olddefconfig)"
make olddefconfig

echo "==> verifying the critical options actually stuck"
REQUIRED="CONFIG_TUN CONFIG_IP_MULTIPLE_TABLES CONFIG_NF_NAT CONFIG_NF_TABLES \
CONFIG_IP_NF_MANGLE CONFIG_IP_NF_NAT CONFIG_NETFILTER_XT_TARGET_CONNMARK \
CONFIG_NETFILTER_XT_TARGET_TCPMSS CONFIG_NETFILTER_XT_MATCH_CONNMARK"
# On x86_64 Firecracker discovers devices via ACPI; if a future CI config disables
# ACPI the guest can't find its root disk. Trip loudly here rather than ship a kernel
# that boot-loops. (aarch64 uses FDT, so it doesn't require ACPI.)
[ "${ARCH}" = "x86_64" ] && REQUIRED="${REQUIRED} CONFIG_ACPI"
missing=0
for sym in $REQUIRED; do
  if ! grep -q "^${sym}=y" .config; then
    echo "  !! missing/disabled: ${sym}"
    missing=1
  fi
done
[ "$missing" -eq 0 ] || { echo "ERROR: critical options not set to =y; aborting." >&2; exit 1; }
echo "  OK: all critical options =y"

echo "==> building the kernel (this takes a while)"
if [ "${ARCH}" = "aarch64" ]; then
  # aarch64 Firecracker boots a PE-format Image (unlike the ELF vmlinux on x86).
  make Image -j"$(nproc)"
  cp -v arch/arm64/boot/Image "${OUT}"
else
  make vmlinux -j"$(nproc)"
  cp -v vmlinux "${OUT}"
fi

# Install to the system path the clawvps CLI expects.
sudo install -D -m 644 "${OUT}" /var/lib/vms/kernel-claw
echo "==> done: /var/lib/vms/kernel-claw"
