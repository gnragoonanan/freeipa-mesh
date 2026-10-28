#!/usr/bin/env bash
#
# FreeIPA unattended install and replica join.
#
# Every input arrives as an environment variable set by the Helm chart, so this
# script contains no addresses, domains, hostnames or credentials of its own and
# can be run and reviewed outside Kubernetes.
#
# It is idempotent. The container's postStart hook runs it on every start, and a
# host that is already configured exits early after making sure the services are
# up, so a restart never attempts to reinstall.
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

LOG_FILE="${IPA_LOG_FILE:-/var/log/freeipa-install.log}"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

log()  { printf '%s  %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"; }
die()  { log "ERROR: $*"; exit 1; }

on_exit() {
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    log "FAILED (exit $rc). The container will be restarted and this script will"
    log "resume; already-completed steps are skipped. Full log: $LOG_FILE"
  fi
}
trap on_exit EXIT

require_env() {
  local name
  for name in "$@"; do
    [ -n "${!name:-}" ] || die "required environment variable $name is empty"
  done
}

# Split a semicolon-separated list into the global array SPLIT_RESULT.
split_list() {
  SPLIT_RESULT=()
  [ -n "${1:-}" ] || return 0
  local IFS=';' item
  read -r -a SPLIT_RESULT <<< "$1"
  # Drop empty members left by trailing separators.
  local -a cleaned=()
  for item in "${SPLIT_RESULT[@]}"; do
    [ -n "$item" ] && cleaned+=("$item")
  done
  SPLIT_RESULT=("${cleaned[@]}")
}

log "======== freeipa-mesh installer starting ========"
log "role=${IPA_ROLE:-?} fqdn=${IPA_FQDN:-?} realm=${IPA_REALM:-?}"

# -----------------------------------------------------------------------------
# 0. Already installed?
# -----------------------------------------------------------------------------
# /etc/ipa/default.conf is written by a successful install and is the cheapest
# reliable marker that this host is already part of a realm.
if [ -f /etc/ipa/default.conf ]; then
  log "FreeIPA is already configured on this host; skipping installation."
  if ! ipactl status >/dev/null 2>&1; then
    log "Services are not running; starting them."
    ipactl start || die "ipactl start failed"
  fi
  log "======== nothing to do, exiting cleanly ========"
  exit 0
fi

require_env IPA_ROLE IPA_HOSTNAME IPA_FQDN IPA_DOMAIN IPA_REALM \
            IPA_ADMIN_USER IPA_ADMIN_PASSWORD IPA_DM_PASSWORD

# -----------------------------------------------------------------------------
# 1. Resolver
# -----------------------------------------------------------------------------
# The pod needs working DNS to reach the package repositories. Once FreeIPA is
# installed with its integrated DNS server, that server answers for the realm.
split_list "${IPA_RESOLVER_NAMESERVERS:-}"
if [ "${#SPLIT_RESULT[@]}" -gt 0 ]; then
  log ">>> Writing /etc/resolv.conf with ${#SPLIT_RESULT[@]} nameserver(s)"
  : > /etc/resolv.conf
  for ns in "${SPLIT_RESULT[@]}"; do
    echo "nameserver $ns" >> /etc/resolv.conf
  done
else
  log ">>> No resolver.nameservers configured; leaving /etc/resolv.conf as-is"
fi

# -----------------------------------------------------------------------------
# 2. Packages
# -----------------------------------------------------------------------------
if [ "${IPA_UPGRADE_PACKAGES:-true}" = "true" ]; then
  log ">>> Refreshing and upgrading base packages"
  dnf -y upgrade --refresh
fi

log ">>> Installing FreeIPA server packages"
packages=(freeipa-server iproute iputils bind-utils curl cronie cronie-anacron)
if [ "${IPA_SETUP_DNS:-true}" = "true" ]; then
  packages+=(freeipa-server-dns)
fi
dnf -y install "${packages[@]}"

# -----------------------------------------------------------------------------
# 3. Name resolution for the mesh
# -----------------------------------------------------------------------------
# FreeIPA refuses to install unless the host's own FQDN resolves, and each
# member must be able to resolve every other member to establish replication.
# Note: the hostname is set here rather than passed as --hostname to the
# installer, which is what the original deployment found to work.
log ">>> Setting hostname to $IPA_FQDN"
hostname "$IPA_FQDN"

split_list "${IPA_HOSTS:-}"
log ">>> Adding ${#SPLIT_RESULT[@]} mesh host entries to /etc/hosts"
for entry in "${SPLIT_RESULT[@]}"; do
  if ! grep -qxF "$entry" /etc/hosts; then
    echo "$entry" >> /etc/hosts
    log "    + $entry"
  fi
done

# -----------------------------------------------------------------------------
# 4. DNS installer arguments
# -----------------------------------------------------------------------------
dns_args=()
if [ "${IPA_SETUP_DNS:-true}" = "true" ]; then
  dns_args+=(--setup-dns)
  split_list "${IPA_DNS_FORWARDERS:-}"
  if [ "${#SPLIT_RESULT[@]}" -gt 0 ]; then
    for fwd in "${SPLIT_RESULT[@]}"; do
      dns_args+=("--forwarder=$fwd")
    done
  else
    dns_args+=(--auto-forwarders)
  fi
fi

# -----------------------------------------------------------------------------
# 5. Install
# -----------------------------------------------------------------------------
# Passwords are passed as command-line arguments because the unattended
# installers accept them no other way. They are briefly visible in the process
# table inside this container. See SECURITY.md.
case "$IPA_ROLE" in
  master)
    log ">>> Installing FreeIPA MASTER for realm $IPA_REALM"
    # shellcheck disable=SC2086
    ipa-server-install \
      --realm="$IPA_REALM" \
      --domain="$IPA_DOMAIN" \
      --admin-password="$IPA_ADMIN_PASSWORD" \
      --ds-password="$IPA_DM_PASSWORD" \
      "${dns_args[@]}" \
      --unattended \
      ${IPA_EXTRA_SERVER_ARGS:-}
    ;;

  replica)
    require_env IPA_MASTER_FQDN
    timeout="${IPA_MASTER_WAIT_TIMEOUT:-900}"
    log ">>> Waiting up to ${timeout}s for master $IPA_MASTER_FQDN LDAP port"
    deadline=$(( SECONDS + timeout ))
    until (exec 3<>"/dev/tcp/${IPA_MASTER_FQDN}/389") 2>/dev/null; do
      exec 3>&- 2>/dev/null || true
      [ "$SECONDS" -lt "$deadline" ] || die "master $IPA_MASTER_FQDN did not answer on port 389 within ${timeout}s"
      sleep 10
    done
    exec 3>&- 2>/dev/null || true
    log "    master is reachable"

    log ">>> Installing FreeIPA REPLICA joining $IPA_MASTER_FQDN"
    # shellcheck disable=SC2086
    ipa-replica-install \
      --principal="$IPA_ADMIN_USER" \
      --admin-password="$IPA_ADMIN_PASSWORD" \
      --server="$IPA_MASTER_FQDN" \
      --domain="$IPA_DOMAIN" \
      --setup-ca \
      "${dns_args[@]}" \
      --unattended \
      ${IPA_EXTRA_REPLICA_ARGS:-}
    ;;

  *)
    die "IPA_ROLE must be \"master\" or \"replica\", got \"$IPA_ROLE\""
    ;;
esac

log ">>> Installation completed"

# -----------------------------------------------------------------------------
# 6. Publish replica A records (master only)
# -----------------------------------------------------------------------------
# The ipa CLI is Kerberos-authenticated, so a ticket is required first. The
# original script called `ipa dnsrecord-add` without obtaining one, which could
# not have succeeded.
if [ "$IPA_ROLE" = "master" ] && [ "${IPA_SETUP_DNS:-true}" = "true" ]; then
  split_list "${IPA_REPLICA_RECORDS:-}"
  if [ "${#SPLIT_RESULT[@]}" -gt 0 ]; then
    log ">>> Obtaining Kerberos ticket for $IPA_ADMIN_USER"
    echo "$IPA_ADMIN_PASSWORD" | kinit "$IPA_ADMIN_USER" \
      || die "kinit failed; cannot publish replica DNS records"

    log ">>> Publishing ${#SPLIT_RESULT[@]} replica A record(s) in $IPA_DOMAIN"
    for record in "${SPLIT_RESULT[@]}"; do
      name="${record%%=*}"
      addr="${record#*=}"
      if ipa dnsrecord-add "$IPA_DOMAIN" "$name" --a-rec="$addr" >/dev/null 2>&1; then
        log "    + $name.$IPA_DOMAIN -> $addr"
      else
        # Most often the record already exists, which is not an error.
        log "    ! could not add $name.$IPA_DOMAIN -> $addr (may already exist)"
      fi
    done
    kdestroy >/dev/null 2>&1 || true
  fi
fi

# -----------------------------------------------------------------------------
# 7. Scheduled backup for DR
# -----------------------------------------------------------------------------
if [ "${IPA_BACKUP_ENABLED:-false}" = "true" ]; then
  data_dir="${IPA_DATA_DIR:-/var/lib/ipa-data}"
  keep_last="${IPA_BACKUP_KEEP_LAST:-5}"
  schedule="${IPA_BACKUP_SCHEDULE:-0 1 * * 0}"

  log ">>> Configuring scheduled backup: '$schedule', keeping $keep_last"

  mkdir -p /etc/freeipa-mesh "$data_dir/backup"
  cat > /etc/freeipa-mesh/backup.conf <<CONF
# Written by the freeipa-mesh installer. Values come from the Helm chart.
DATA_DIR=$data_dir
KEEP_LAST=$keep_last
CONF

  # Quoted heredoc: the wrapper reads its settings at run time instead of
  # having them baked in, so changing the chart values and restarting is enough.
  cat > /usr/local/sbin/ipa-mesh-backup <<'WRAPPER'
#!/usr/bin/env bash
# Run ipa-backup, copy the result to persistent storage and prune old copies.
set -euo pipefail
. /etc/freeipa-mesh/backup.conf

ipa-backup

mkdir -p "$DATA_DIR/backup"
cp -r /var/lib/ipa/backup/. "$DATA_DIR/backup/"

# Keep only the most recent $KEEP_LAST backups in each location.
prune() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  ( cd "$dir" && ls -1dt -- */ 2>/dev/null | tail -n "+$((KEEP_LAST + 1))" \
      | while IFS= read -r old; do rm -rf -- "$old"; done )
}
prune /var/lib/ipa/backup
prune "$DATA_DIR/backup"
WRAPPER
  chmod 0750 /usr/local/sbin/ipa-mesh-backup

  # Replace any previous entry rather than appending a duplicate on restart.
  cron_line="$schedule /usr/local/sbin/ipa-mesh-backup >> /var/log/ipa-mesh-backup.log 2>&1"
  { crontab -l 2>/dev/null | grep -v 'ipa-mesh-backup' || true; echo "$cron_line"; } | crontab -

  systemctl enable --now crond >/dev/null 2>&1 || log "    ! could not enable crond"
  log "    backup wrapper installed at /usr/local/sbin/ipa-mesh-backup"
else
  log ">>> Scheduled backup disabled"
fi

log "======== freeipa-mesh installer complete ========"
log "Web UI: https://$IPA_FQDN/  (user: $IPA_ADMIN_USER)"
