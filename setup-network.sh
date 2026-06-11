#!/usr/bin/env bash
# setup-network.sh — VM bridge (br0) + NAT + isolation firewall (idempotent)
# Installed as /usr/sbin/vps-setup-network; run at boot by vps-network.service.
#
# Isolation model (containing a misbehaving agent):
#   VM → internet            allow (NAT)
#   VM ↔ VM                  block (L2: isolated bridge ports / L3: br0→br0 DROP)
#   VM → host (10.42.0.1)    block (VPS-IN chain)
#   VM → home LAN / tailnet  block (private + CGNAT destination DROP)
#   tailnet → VM (ssh etc.)  allow (inbound via the subnet router)
# Addressing: 10.42.0.0/16, gateway (host) 10.42.0.1, VM pool from 10.42.0.10.
set -euo pipefail

BR="br0"
BR_CIDR="10.42.0.1/16"
NET="10.42.0.0/16"
TS_IF="tailscale0"

# The default route may not exist yet right after boot → wait up to 30s.
# Skip tailscale0 (it becomes the default route when an exit node is in use).
EGRESS=""
for _ in $(seq 1 30); do
  EGRESS="$(ip route show default | awk -v ts="${TS_IF}" '$5 != ts {print $5; exit}')"
  [ -n "${EGRESS}" ] && break
  sleep 1
done
[ -n "${EGRESS}" ] || { echo "ERROR: no default route — cannot determine egress interface" >&2; exit 1; }

if ! ip link show "${BR}" >/dev/null 2>&1; then
  ip link add "${BR}" type bridge
fi
ip addr replace "${BR_CIDR}" dev "${BR}"
ip link set "${BR}" up

sysctl -qw net.ipv4.ip_forward=1

# NAT (idempotent)
iptables -t nat -C POSTROUTING -s "${NET}" -o "${EGRESS}" -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -s "${NET}" -o "${EGRESS}" -j MASQUERADE

# Remove pre-isolation legacy rules from older versions, if present.
iptables -D FORWARD -i "${BR}" -o "${BR}" -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i "${BR}" -o "${EGRESS}" -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i "${EGRESS}" -o "${BR}" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

# ---- FORWARD: dedicated chain (flushed and rebuilt = idempotent) ----
iptables -N VPS-FWD 2>/dev/null || true
iptables -F VPS-FWD
iptables -C FORWARD -j VPS-FWD 2>/dev/null || iptables -I FORWARD 1 -j VPS-FWD

iptables -A VPS-FWD -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A VPS-FWD -i "${BR}" -o "${BR}" -j DROP                  # VM↔VM (incl. gateway-hairpin routing)
iptables -A VPS-FWD -i "${TS_IF}" -o "${BR}" -j ACCEPT             # tailnet → VM (ssh inbound)
iptables -A VPS-FWD -i "${BR}" -d 10.0.0.0/8      -j DROP          # VM → private/home LAN/CGNAT: blocked
iptables -A VPS-FWD -i "${BR}" -d 172.16.0.0/12   -j DROP
iptables -A VPS-FWD -i "${BR}" -d 192.168.0.0/16  -j DROP
iptables -A VPS-FWD -i "${BR}" -d 100.64.0.0/10   -j DROP
iptables -A VPS-FWD -i "${BR}" -d 169.254.0.0/16  -j DROP
iptables -A VPS-FWD -i "${BR}" -o "${EGRESS}" -j ACCEPT            # VM → internet
iptables -A VPS-FWD -i "${BR}" -j DROP                             # everything else (e.g. toward tailscale0)

# ---- INPUT: block VM → host ----
iptables -N VPS-IN 2>/dev/null || true
iptables -F VPS-IN
iptables -C INPUT -i "${BR}" -j VPS-IN 2>/dev/null || iptables -I INPUT 1 -i "${BR}" -j VPS-IN

iptables -A VPS-IN -m state --state ESTABLISHED,RELATED -j ACCEPT  # replies to host-initiated traffic only
iptables -A VPS-IN -j DROP

echo "OK: ${BR}=${BR_CIDR}, NAT ${NET} -> ${EGRESS}, isolation firewall (VPS-FWD/VPS-IN) applied"
