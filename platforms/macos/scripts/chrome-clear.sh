#!/bin/sh

export PATH=/usr/bin:/bin:/usr/sbin:/sbin
set -vex
currentUser=$(echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }')
if [ -z "$currentUser" ] || [ "$currentUser" = "loginwindow" ]; then
	echo "ERROR: No user logged in at console." >&2; exit 1
fi
uid=$(id -u "$currentUser")
USER_HOME="/Users/${currentUser}"

runAsUser() {
	launchctl asuser "$uid" sudo -u "$currentUser" "$@"
}

set -vex
if [ ! -e "/Applications/Google Chrome.app" ]; then
	echo "Google Chrome is not installed."; exit 1
fi

echo "Closing Google Chrome..."
killall "Google Chrome" 2>/dev/null || true
sleep 2

echo "Clearing cache and cookies..."
runAsUser rm -rf "${USER_HOME}/Library/Application Support/Google/Chrome/Default/Cookies" 2>/dev/null || true
runAsUser rm -rf "${USER_HOME}/Library/Caches/Google" 2>/dev/null || true

echo "Relaunching Google Chrome..."
runAsUser /usr/bin/open "/Applications/Google Chrome.app"

echo "Done."
