#!/bin/sh
# Run this on the Proxmox host after uploading the template.
# Adjust CTID, storage, bridge, and the template filename as needed.

CTID="${CTID:-201}"
TEMPLATE="${TEMPLATE:-local:vztmpl/openwrt-25.12.5-x86-64-pve-lxc-YYYYMMDD-HHMM.tar.gz}"
STORAGE="${STORAGE:-local-lvm}"
BRIDGE="${BRIDGE:-vmbr0}"
HOSTNAME="${HOSTNAME:-openwrt}"

pct create "$CTID" "$TEMPLATE" \
	--ostype unmanaged \
	--arch amd64 \
	--hostname "$HOSTNAME" \
	--cores 2 \
	--memory 256 \
	--swap 0 \
	--rootfs "${STORAGE}:4" \
	--features nesting=1 \
	--unprivileged 0 \
	--net0 "name=eth0,bridge=${BRIDGE}"

pct start "$CTID"
echo "Container $CTID started. Set root password with: pct exec $CTID -- passwd"
echo "If LAN is DHCP, look up the address with: pct exec $CTID -- ip -4 addr show"
