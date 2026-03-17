#!/usr/bin/env bash

# -e: Immediately exit if any command has a non-zero exit status.
# -x: Print all executed commands to the terminal.
# -u: Exit if an undefined variable is used.
# -o pipefail: Exit if any command in a pipeline fails.
set -exuo pipefail

FLEET_GITOPS_DIR="${FLEET_GITOPS_DIR:-.}"
FLEET_GLOBAL_FILE="${FLEET_GLOBAL_FILE:-$FLEET_GITOPS_DIR/default.yml}"
FLEETCTL="${FLEETCTL:-fleetctl}"
FLEET_DRY_RUN_ONLY="${FLEET_DRY_RUN_ONLY:-false}"
FLEET_DELETE_OTHER_TEAMS="${FLEET_DELETE_OTHER_TEAMS:-true}"

# Validate that global file contains org_settings
grep -Exq "^org_settings:.*" "$FLEET_GLOBAL_FILE"

# Copy/pasting raw SSO metadata into GitHub secrets will result in malformed yaml.
# Adds spaces to all but the first line of metadata keeps the  multiline string in bounds.
# See README for more information

# FLEET_SSO_METADATA=$( sed '2,$s/^/       /' <<<  "${FLEET_MDM_SSO_METADATA}")
# FLEET_MDM_SSO_METADATA=$( sed '2,$s/^/       /' <<<  "${FLEET_MDM_SSO_METADATA}")

if compgen -G "$FLEET_GITOPS_DIR/fleets/*.yml" > /dev/null; then
  # Validate that every team has a unique name.
  # This is a limited check that assumes all team files contain the phrase: `name: <team_name>`
  ! perl -nle 'print $1 if /^name:\s*(.+)$/' "$FLEET_GITOPS_DIR"/fleets/*.yml | sort | uniq -d | grep . -cq
fi

# Build fleet file args
fleet_args=()
for team_file in "$FLEET_GITOPS_DIR"/fleets/*.yml; do
  if [ -f "$team_file" ]; then
    fleet_args+=(-f "$team_file")
  fi
done

delete_args=()
if [ "$FLEET_DELETE_OTHER_TEAMS" = true ]; then
  delete_args+=(--delete-other-teams)
fi

# Phase 1: Apply global config only (includes VPP).
# Running without fleet files means Fleet can fully clear and then re-apply VPP
# fleet assignments at the end of this run, with nothing that can fail in between.
$FLEETCTL gitops -f "$FLEET_GLOBAL_FILE" --dry-run

if [ "$FLEET_DRY_RUN_ONLY" = true ]; then
  exit 0
fi

$FLEETCTL gitops -f "$FLEET_GLOBAL_FILE"
# After Phase 1: VPP fleet assignments are correctly applied.

# Phase 2: Apply fleet team files only — no global config, so applied fleet config
# does not run and VPP assignments are preserved from Phase 1.
# Unassigned fleet's app_store_apps now succeed because VPP is correctly assigned.
if [ "${#fleet_args[@]}" -gt 0 ]; then
  $FLEETCTL gitops "${fleet_args[@]}" "${delete_args[@]}" --dry-run
  $FLEETCTL gitops "${fleet_args[@]}" "${delete_args[@]}"
fi
