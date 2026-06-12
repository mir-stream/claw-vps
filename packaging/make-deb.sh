#!/usr/bin/env bash
# packaging/make-deb.sh — build claw-vps .deb packages (arm64 + amd64)
# Run on Linux: ./make-deb.sh          Output: ./dist/claw-vps_<ver>_<arch>.deb
# Override the version: VERSION=0.5.0 ./make-deb.sh
# Set a homepage for the control file: HOMEPAGE=https://github.com/you/claw-vps ./make-deb.sh
#
# Bundled: clawvps CLI, firecracker binary (pinned version, with its Apache-2.0
# LICENSE/NOTICE), image build tools, systemd units, example Dockerfiles.
# NOT bundled: golden images / guest kernel — built after install via
# `clawvps setup kernel` / `clawvps setup base`.
set -euo pipefail

VERSION="${VERSION:-0.7.0}"
HOMEPAGE="${HOMEPAGE:-}"
FC_VERSION="v1.16.0"
SRC="$(cd "$(dirname "$0")/.." && pwd)"     # the vps/ directory
DIST="$(cd "$(dirname "$0")" && pwd)/dist"
mkdir -p "${DIST}"

fetch() {  # fetch <url> <cache-file>
  if [ ! -f "$2" ]; then
    curl -fsSL "$1" > "$2"
  fi
}

build_one() {
  local deb_arch="$1" fc_arch="$2"
  local stage; stage="$(mktemp -d)"
  echo "==> assembling ${deb_arch} package"

  # --- files ---
  install -D -m 755 "${SRC}/clawvps"               "${stage}/usr/bin/clawvps"
  install -D -m 755 "${SRC}/setup-network.sh" "${stage}/usr/sbin/vps-setup-network"
  install -D -m 755 "${SRC}/build-kernel.sh"  "${stage}/usr/share/claw-vps/build-kernel.sh"
  install -D -m 755 "${SRC}/build-base.sh"    "${stage}/usr/share/claw-vps/build-base.sh"
  install -D -m 644 "${SRC}/examples/openclaw.Dockerfile" "${stage}/usr/share/claw-vps/examples/openclaw.Dockerfile"
  install -D -m 644 "${SRC}/firecracker@.service"  "${stage}/lib/systemd/system/firecracker@.service"
  install -D -m 644 "${SRC}/vps-network.service"   "${stage}/lib/systemd/system/vps-network.service"
  # needrestart override: keep apt upgrades from bouncing running VMs (see file header).
  install -D -m 644 "${SRC}/needrestart-claw-vps.conf" "${stage}/etc/needrestart/conf.d/claw-vps.conf"

  # --- bundled firecracker binary (per arch) + its license ---
  local bin_cache="${DIST}/.fc-${FC_VERSION}-${fc_arch}"
  if [ ! -f "${bin_cache}" ]; then
    echo "    downloading firecracker ${FC_VERSION} ${fc_arch}"
    curl -fsSL "https://github.com/firecracker-microvm/firecracker/releases/download/${FC_VERSION}/firecracker-${FC_VERSION}-${fc_arch}.tgz" \
      | tar -xzO "release-${FC_VERSION}-${fc_arch}/firecracker-${FC_VERSION}-${fc_arch}" > "${bin_cache}"
  fi
  install -D -m 755 "${bin_cache}" "${stage}/usr/sbin/firecracker"

  fetch "https://raw.githubusercontent.com/firecracker-microvm/firecracker/${FC_VERSION}/LICENSE" "${DIST}/.fc-LICENSE"
  fetch "https://raw.githubusercontent.com/firecracker-microvm/firecracker/${FC_VERSION}/NOTICE"  "${DIST}/.fc-NOTICE"
  install -D -m 644 "${DIST}/.fc-LICENSE" "${stage}/usr/share/doc/claw-vps/firecracker/LICENSE"
  install -D -m 644 "${DIST}/.fc-NOTICE"  "${stage}/usr/share/doc/claw-vps/firecracker/NOTICE"

  # --- docs (Debian-style copyright + changelog) ---
  install -D -m 644 "${SRC}/CHANGELOG.md" "${stage}/usr/share/doc/claw-vps/changelog"
  install -D -m 644 "${SRC}/LICENSE"      "${stage}/usr/share/doc/claw-vps/copyright"

  # --- metadata ---
  mkdir -p "${stage}/DEBIAN"
  {
    echo "Package: claw-vps"
    echo "Version: ${VERSION}"
    echo "Architecture: ${deb_arch}"
    echo "Maintainer: mir <repeat.language@gmail.com>"
    echo "Depends: iptables, iproute2, debootstrap, curl, ca-certificates"
    echo "Recommends: docker.io"
    [ -n "${HOMEPAGE}" ] && echo "Homepage: ${HOMEPAGE}"
    echo "Section: admin"
    echo "Priority: optional"
    echo "Description: Firecracker mini-VPS provisioner (clawvps CLI)"
    echo " Stamps out isolated Firecracker microVMs with SSH access via"
    echo " Tailscale subnet routing. Golden images are defined with plain"
    echo " Dockerfiles (clawvps build); foundation images are built once with"
    echo " clawvps setup kernel / clawvps setup base."
  } > "${stage}/DEBIAN/control"

  # Mark the needrestart override as a conffile so local edits survive upgrades.
  echo "/etc/needrestart/conf.d/claw-vps.conf" > "${stage}/DEBIAN/conffiles"

  cat > "${stage}/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
mkdir -p /var/lib/vms/images
systemctl daemon-reload || true
systemctl enable --now vps-network.service || true
if [ "$1" = "configure" ] && [ -z "$2" ]; then   # fresh install only (not upgrades)
  echo ""
  echo "claw-vps installed. Get started:"
  echo "  sudo clawvps init            # one-time setup (subnet route + SSH key)"
  echo "  sudo clawvps setup kernel    # build the guest kernel (one-time)"
  echo "  sudo clawvps setup base      # build the base golden image (one-time)"
  echo "  sudo clawvps create first    # create a VM"
fi
EOF
  chmod 755 "${stage}/DEBIAN/postinst"

  cat > "${stage}/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
# Stop the network unit only on full removal (not upgrades).
# Running VMs (firecracker@*) are deliberately left alone.
if [ "$1" = "remove" ]; then
  systemctl disable --now vps-network.service || true
fi
EOF
  chmod 755 "${stage}/DEBIAN/prerm"

  cat > "${stage}/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
systemctl daemon-reload || true
if [ "$1" = "purge" ]; then
  # Golden images and VM disks are deliberately kept (data protection).
  [ -d /var/lib/vms ] && echo "Note: VM data remains in /var/lib/vms (delete manually if desired)"
fi
EOF
  chmod 755 "${stage}/DEBIAN/postrm"

  dpkg-deb --build --root-owner-group "${stage}" "${DIST}/claw-vps_${VERSION}_${deb_arch}.deb"
  rm -rf "${stage}"
}

build_one arm64 aarch64
build_one amd64 x86_64

echo "==> done:"
ls -lh "${DIST}"/claw-vps_${VERSION}_*.deb
