#!/bin/bash
# Deploy fleet-watchdog: a systemd service that detects deliberate
# unenrollment of fleetd and signals Fleet via API.
#
# Deployed via Fleet as a script — runs once as root.
# Creates:
#   /usr/local/bin/fleet-watchdog   — the watchdog loop
#   /etc/systemd/system/fleet-watchdog.service — systemd unit
#   /etc/apt/apt.conf.d/99-fleet-hold — dpkg removal block
#   /etc/fleet-watchdog.conf — config (Fleet URL + token)

set -e

# ── Config file (populated from Fleet env vars at deploy time) ────────
mkdir -p /etc
cat > /etc/fleet-watchdog.conf <<'CONF'
# Fleet watchdog configuration
# FLEET_URL and FLEET_API_TOKEN are required for API notifications.
# If missing, the watchdog still protects locally and writes tamper flags.
FLEET_WATCHDOG_URL=""
FLEET_WATCHDOG_TOKEN=""
CONF
chmod 600 /etc/fleet-watchdog.conf

# ── Detect Fleet package name(s) ─────────────────────────────────────
# Fleet ships as either "fleetd" or "fleet-osquery" depending on version/distro.
FLEET_PKGS=""
for pkg in fleetd fleet-osquery; do
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    FLEET_PKGS="$FLEET_PKGS $pkg"
  fi
done
FLEET_PKGS=$(echo "$FLEET_PKGS" | xargs)  # trim whitespace
if [ -z "$FLEET_PKGS" ]; then
  echo "WARNING: Neither fleetd nor fleet-osquery package found. Watchdog will still install." >&2
  FLEET_PKGS="fleetd fleet-osquery"
fi

# ── dpkg hook: block removal of Fleet packages ──────────────────────
cat > /etc/apt/apt.conf.d/99-fleet-hold <<'APTCONF'
// Prevent removal of Fleet packages (fleetd / fleet-osquery) via apt
DPkg::Pre-Invoke {
  "for p in fleetd fleet-osquery; do dpkg-query -s $p >/dev/null 2>&1 && dpkg --get-selections $p 2>/dev/null | grep -q 'deinstall' && echo \"ERROR: Removal of $p is blocked by fleet-watchdog.\" >&2 && exit 1; done; true";
};
APTCONF

# Also set dpkg hold on detected packages
for pkg in $FLEET_PKGS; do
  dpkg --set-selections <<< "$pkg hold" 2>/dev/null || true
done

# ── Watchdog script ───────────────────────────────────────────────────
cat > /usr/local/bin/fleet-watchdog <<'WATCHDOG'
#!/bin/bash
# fleet-watchdog: monitors fleetd health and detects deliberate tampering.
#
# Deliberate actions detected:
#   1. fleetd package removed (dpkg -s fails)
#   2. fleetd service disabled (systemctl is-enabled fails)
#   3. fleetd service stopped for >120s (grace period for updates)
#   4. fleetd enrollment config deleted
#
# On detection: writes flag to /var/run/fleet-tamper-detected,
# logs to syslog, and calls Fleet API if configured.

TAMPER_FLAG="/var/run/fleet-tamper-detected"
CONF_FILE="/etc/fleet-watchdog.conf"
STOP_TIMESTAMP=""
GRACE_SECONDS=120

log() {
  logger -t fleet-watchdog -p auth.warning "$1"
}

notify_fleet() {
  local reason="$1"

  # Source config for API credentials
  if [ -f "$CONF_FILE" ]; then
    . "$CONF_FILE"
  fi

  # Write local tamper flag (queryable via osquery)
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $reason" >> "$TAMPER_FLAG"
  chmod 644 "$TAMPER_FLAG"

  log "TAMPER DETECTED: $reason"

  # Call Fleet API if configured
  if [ -n "$FLEET_WATCHDOG_URL" ] && [ -n "$FLEET_WATCHDOG_TOKEN" ]; then
    local hostname
    hostname=$(hostname)
    local hw_serial
    hw_serial=$(cat /sys/class/dmi/id/product_serial 2>/dev/null || echo "unknown")

    curl -sS -X POST \
      -H "Authorization: Bearer $FLEET_WATCHDOG_TOKEN" \
      -H "Content-Type: application/json" \
      "$FLEET_WATCHDOG_URL/api/latest/fleet/activities" \
      -d "{\"type\":\"fleet_watchdog_tamper\",\"details\":{\"reason\":\"$reason\",\"hostname\":\"$hostname\",\"hardware_serial\":\"$hw_serial\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}}" \
      2>/dev/null || log "Failed to notify Fleet API"
  fi
}

check_package() {
  # Fleet ships as "fleetd" or "fleet-osquery" — check both
  local found=0
  for pkg in fleetd fleet-osquery; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      found=1
      break
    fi
  done
  if [ "$found" -eq 0 ]; then
    notify_fleet "Fleet package has been removed (checked: fleetd, fleet-osquery)"
    return 1
  fi
  return 0
}

# Detect the Fleet service name (orbit.service or fleetd.service)
detect_fleet_service() {
  for svc in orbit.service fleetd.service; do
    if systemctl list-unit-files "$svc" >/dev/null 2>&1; then
      if systemctl list-unit-files "$svc" 2>/dev/null | grep -q "$svc"; then
        echo "$svc"
        return
      fi
    fi
  done
  echo "orbit.service"  # default
}
FLEET_SERVICE=$(detect_fleet_service)

check_service_enabled() {
  if ! systemctl is-enabled "$FLEET_SERVICE" >/dev/null 2>&1; then
    notify_fleet "$FLEET_SERVICE has been disabled"
    # Re-enable it
    systemctl enable "$FLEET_SERVICE" 2>/dev/null || true
    return 1
  fi
  return 0
}

check_service_running() {
  if systemctl is-active "$FLEET_SERVICE" >/dev/null 2>&1; then
    # Service is running — clear any stop timestamp
    STOP_TIMESTAMP=""
    return 0
  fi

  # Service is not running
  local now
  now=$(date +%s)

  if [ -z "$STOP_TIMESTAMP" ]; then
    # First detection — start grace period (allows for updates/restarts)
    STOP_TIMESTAMP="$now"
    log "$FLEET_SERVICE stopped — starting ${GRACE_SECONDS}s grace period"
    return 0
  fi

  local elapsed=$(( now - STOP_TIMESTAMP ))
  if [ "$elapsed" -ge "$GRACE_SECONDS" ]; then
    notify_fleet "$FLEET_SERVICE stopped for ${elapsed}s (exceeds ${GRACE_SECONDS}s grace period)"
    # Attempt restart
    systemctl start "$FLEET_SERVICE" 2>/dev/null || true
    STOP_TIMESTAMP=""
    return 1
  fi

  return 0
}

check_enrollment() {
  # Fleet enrollment data lives here
  local enroll_path="/opt/orbit/secret.txt"
  if [ ! -f "$enroll_path" ]; then
    # Also check alternate location
    enroll_path="/etc/default/orbit"
    if [ ! -f "$enroll_path" ]; then
      notify_fleet "Fleet enrollment configuration has been deleted"
      return 1
    fi
  fi
  return 0
}

# ── Main loop ─────────────────────────────────────────────────────────
log "fleet-watchdog started"

while true; do
  check_package
  check_service_enabled
  check_service_running
  check_enrollment
  sleep 30
done
WATCHDOG
chmod 755 /usr/local/bin/fleet-watchdog

# ── systemd unit ──────────────────────────────────────────────────────
cat > /etc/systemd/system/fleet-watchdog.service <<'UNIT'
[Unit]
Description=Fleet Watchdog — prevents fleetd unenrollment
After=network.target orbit.service fleetd.service
Wants=orbit.service

[Service]
Type=simple
ExecStart=/usr/local/bin/fleet-watchdog
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable fleet-watchdog.service
systemctl start fleet-watchdog.service

echo "fleet-watchdog installed and running."
