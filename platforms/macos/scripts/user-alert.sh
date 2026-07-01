#!/bin/sh

# Original code from Armin Briegel - Scripting OS X
# https://scriptingosx.com/2020/08/running-a-command-as-another-user/

# variable and function declarations
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

# get the currently logged in user
currentUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )

# global check if there is a user logged in
if [ -z "$currentUser" -o "$currentUser" = "loginwindow" ]; then
  echo "no user logged in, cannot proceed"
  exit 1
fi

uid=$(id -u "$currentUser")

runAsUser() {  
  if [ "$currentUser" != "loginwindow" ]; then
    launchctl asuser "$uid" sudo -u "$currentUser" "$@"
  else
    echo "no user logged in"
    # uncomment the exit command
    # to make the function exit with an error when no user is logged in
    # exit 1
  fi
}

# The command to run as logged-in user.
# runCommand=$(osascript -e "display dialog \"Alert delivered to $currentUser, UID $uid\"")

# Runs the command as the GUI logged-in user using the subroutine.
runAsUser osascript -e "display dialog \"Alert delivered to $currentUser, UID $uid\""

# Runs the command as the script-running user with no consideration.
# sh "$runCommand"

exit 0;
