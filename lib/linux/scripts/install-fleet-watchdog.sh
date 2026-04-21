#!/bin/bash
# Deploy fleet-watchdog: a lightweight systemd service that detects
# deliberate unenrollment of fleetd and signals Fleet via API.
#
# Deployed via Fleet as a script — runs once as root.
# Creates:
#   /usr/local/bin/fleet-watchdog              — the watchdog loop
#   /etc/systemd/system/fleet-watchdog.service — systemd unit
#   /etc/fleet-watchdog.conf                   — config (Fleet URL + token)

set -e

# ── Config file ──────────────────────────────────────────────────────
mkdir -p /etc
cat > /etc/fleet-watchdog.conf <<'CONF'
# Fleet watchdog configuration
# Populate these to enable API notifications on tamper detection.
# If empty, the watchdog still logs to syslog and writes tamper flags.
FLEET_WATCHDOG_URL=""
FLEET_WATCHDOG_TOKEN=""
CONF
chmod 600 /etc/fleet-watchdog.conf

# ── Watchdog script ──────────────────────────────────────────────────
cat > /usr/local/bin/fleet-watchdog <<'WATCHDOG'
#!/bin/bash
# fleet-watchdog: monitors Fleet agent health and detects deliberate tampering.
#
# Checks every 30 seconds for:
#   1. Fleet package removed (fleet-osquery or fleetd)
#   2. Fleet service disabled
#   3. Fleet service stopped beyond a grace period (allows for updates)
#   4. Fleet enrollment config deleted
#
# On detection: logs to syslog, writes /var/run/fleet-tamper-detected
# (queryable by osquery), and calls the Fleet API if configured.

TAMPER_FLAG="/var/run/fleet-tamper-detected"
CONF_FILE="/etc/fleet-watchdog.conf"
STOP_TIMESTAMP=""
GRACE_SECONDS=120

log() { logger -t fleet-watchdog -p auth.warning "$1"; }

notify_fleet() {
  local reason="$1"
  log "TAMPER DETECTED: $reason"

  # Write local tamper flag (queryable via osquery policy)
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $reason" >> "$TAMPER_FLAG"
  chmod 644 "$TAMPER_FLAG"

  # Source config for API credentials
  if [ -f "$CONF_FILE" ]; then
    . "$CONF_FILE"
  fi

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
  for pkg in fleetd fleet-osquery; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      return 0
    fi
  done
  notify_fleet "Fleet package has been removed (checked: fleetd, fleet-osquery)"
  return 1
}

# Detect the Fleet service name once at startup
detect_fleet_service() {
  for svc in orbit.service fleetd.service; do
    if systemctl list-unit-files "$svc" 2>/dev/null | grep -q "$svc"; then
      echo "$svc"
      return
    fi
  done
  echo "orbit.service"
}
FLEET_SERVICE=$(detect_fleet_service)

check_service_enabled() {
  if ! systemctl is-enabled "$FLEET_SERVICE" >/dev/null 2>&1; then
    notify_fleet "$FLEET_SERVICE has been disabled"
    return 1
  fi
  return 0
}

check_service_running() {
  if systemctl is-active "$FLEET_SERVICE" >/dev/null 2>&1; then
    STOP_TIMESTAMP=""
    return 0
  fi

  local now
  now=$(date +%s)

  if [ -z "$STOP_TIMESTAMP" ]; then
    STOP_TIMESTAMP="$now"
    log "$FLEET_SERVICE stopped — starting ${GRACE_SECONDS}s grace period"
    return 0
  fi

  local elapsed=$(( now - STOP_TIMESTAMP ))
  if [ "$elapsed" -ge "$GRACE_SECONDS" ]; then
    notify_fleet "$FLEET_SERVICE stopped for ${elapsed}s (exceeds ${GRACE_SECONDS}s grace period)"
    STOP_TIMESTAMP=""
    return 1
  fi
  return 0
}

check_enrollment() {
  if [ -f /opt/orbit/secret.txt ] || [ -f /etc/default/orbit ]; then
    return 0
  fi
  notify_fleet "Fleet enrollment configuration has been deleted"
  return 1
}

# ── Main loop ────────────────────────────────────────────────────────
log "fleet-watchdog started (monitoring $FLEET_SERVICE)"

while true; do
  check_package
  check_service_enabled
  check_service_running
  check_enrollment
  sleep 30
done
WATCHDOG
chmod 755 /usr/local/bin/fleet-watchdog

# ── systemd unit ─────────────────────────────────────────────────────
cat > /etc/systemd/system/fleet-watchdog.service <<'UNIT'
[Unit]
Description=Fleet Watchdog — detects fleetd tampering
After=network.target orbit.service fleetd.service

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
systemctl restart fleet-watchdog.service

echo "fleet-watchdog installed and running."
