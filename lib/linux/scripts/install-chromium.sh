#!/bin/bash

# Install Chromium
apt-get update && apt-get install -y chromium-browser

# --- Chrome managed policies (enforced, user cannot override) ---
# Chromium on Ubuntu/Debian may read from either path
mkdir -p /etc/chromium-browser/policies/managed /etc/chromium/policies/managed
for dir in /etc/chromium-browser/policies/managed /etc/chromium/policies/managed; do
  cat > "$$dir/chromium-fleet.json" <<'POLICY'
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
  chmod 644 "$$dir/chromium-fleet.json"
done

# --- Chromium initial preferences (applied on first profile creation) ---
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
