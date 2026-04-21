#!/bin/bash

# Install Chromium (works with both deb and snap transitional package)
apt-get update && apt-get install -y chromium-browser

echo "fleet: configuring Chromium managed policies..."

# --- Chrome managed policies (enforced, user cannot override) ---
# Both snap and deb Chromium read from these directories.
# NOTE: No shell variables allowed — Fleet expands them at deploy time.
mkdir -p /etc/chromium-browser/policies/managed /etc/chromium/policies/managed

cat > /etc/chromium-browser/policies/managed/chromium-fleet.json <<'POLICY'
{
  "HomepageLocation": "https://fleetdm.com",
  "HomepageIsNewTabPage": false,
  "RestoreOnStartup": 4,
  "RestoreOnStartupURLs": ["https://fleetdm.com"],
  "DefaultBrowserSettingEnabled": false,
  "SyncDisabled": true,
  "BrowserSignin": 0,
  "ConfirmToQuit": false
}
POLICY
chmod 644 /etc/chromium-browser/policies/managed/chromium-fleet.json
cp /etc/chromium-browser/policies/managed/chromium-fleet.json /etc/chromium/policies/managed/chromium-fleet.json
echo "fleet: wrote managed policies"

# --- Chromium initial preferences (applied on first profile creation) ---
# Only written for deb installs; snap Chromium has a read-only app dir
# so initial_preferences cannot be placed there.
if [ -d /usr/lib/chromium-browser ]; then
  cat > /usr/lib/chromium-browser/initial_preferences <<'PREFS'
{
  "browser": {
    "has_seen_welcome_page": true,
    "confirm_to_quit": false,
    "check_default_browser": false
  },
  "first_run_tabs": [],
  "distribution": {
    "skip_first_run_ui": true,
    "suppress_first_run_default_browser_prompt": true
  }
}
PREFS
  chmod 644 /usr/lib/chromium-browser/initial_preferences
  echo "fleet: wrote /usr/lib/chromium-browser/initial_preferences"
elif [ -d /usr/lib/chromium ]; then
  cat > /usr/lib/chromium/initial_preferences <<'PREFS'
{
  "browser": {
    "has_seen_welcome_page": true,
    "confirm_to_quit": false,
    "check_default_browser": false
  },
  "first_run_tabs": [],
  "distribution": {
    "skip_first_run_ui": true,
    "suppress_first_run_default_browser_prompt": true
  }
}
PREFS
  chmod 644 /usr/lib/chromium/initial_preferences
  echo "fleet: wrote /usr/lib/chromium/initial_preferences"
else
  echo "fleet: snap Chromium detected — skipping initial_preferences (managed policies still applied)"
fi

echo "fleet: Chromium configuration complete."
