#!/bin/bash

# Configure Vivaldi via Chrome managed policies and initial preferences.
# Runs as root post-install, before any user launches the browser.

# --- Chrome managed policies (enforced, user cannot override) ---
mkdir -p /etc/chromium/policies/managed
cat > /etc/chromium/policies/managed/vivaldi-fleet.json <<'POLICY'
{
  "HomepageLocation": "https://fleetdm.com",
  "HomepageIsNewTabPage": false,
  "RestoreOnStartup": 4,
  "RestoreOnStartupURLs": ["https://fleetdm.com"],
  "DefaultBrowserSettingEnabled": false,
  "SyncDisabled": true
}
POLICY
chmod 644 /etc/chromium/policies/managed/vivaldi-fleet.json

# --- Vivaldi initial preferences (applied on first profile creation) ---
# This file seeds settings for new profiles. Vivaldi-specific features
# (ad/tracker blocker, theme, tab position, mail/calendar/feeds) live
# under the "vivaldi" key in the Chromium preferences JSON.
VIVALDI_DIR=$(find /opt -maxdepth 1 -type d -name 'vivaldi*' 2>/dev/null | head -1)
if [ -z "$VIVALDI_DIR" ]; then
  VIVALDI_DIR="/opt/vivaldi"
fi

cat > "$VIVALDI_DIR/initial_preferences" <<'PREFS'
{
  "vivaldi": {
    "content_blocker": {
      "tracker_blocking": 2,
      "ad_blocking": 2
    },
    "themes": {
      "system": 1
    },
    "address_bar": {
      "tab_position": 0
    },
    "mail": {
      "mail_feature_enabled": false
    },
    "calendar": {
      "calendar_feature_enabled": false
    },
    "feeds": {
      "feeds_feature_enabled": false
    },
    "sync": {
      "active": false
    },
    "welcome": {
      "seen_version": "99.0"
    },
    "startup": {
      "default_browser_check": false
    }
  },
  "browser": {
    "has_seen_welcome_page": true
  },
  "first_run_tabs": []
}
PREFS
chmod 644 "$VIVALDI_DIR/initial_preferences"
