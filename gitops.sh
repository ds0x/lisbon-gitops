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

delete_args=()
if [ "$FLEET_DELETE_OTHER_TEAMS" = true ]; then
  delete_args+=(--delete-other-teams)
fi

# ─────────────────────────────────────────────────────────────────────────────
# Two-Phase VPP Fix
#
# Problem: `fleetctl gitops` always runs "applied fleet config" when default.yml
# is included. This clears VPP fleet assignments mid-run (before team files are
# processed). If any team file depends on VPP (e.g. unassigned.yml's
# app_store_apps), the run fails with "No available VPP Token".
#
# Solution:
#   Phase 1 - Run default.yml + all team files, but replace unassigned.yml with
#             a temporary version that has app_store_apps removed. This satisfies
#             Fleet's team-name validation for the VPP "Unassigned" fleet, allows
#             all other teams to be applied, and lets Fleet re-apply VPP
#             assignments (including Unassigned) at the end of the run.
#
#   Phase 2 - Run unassigned.yml only (no default.yml -> no "applied fleet
#             config" -> no VPP clearing). VPP is still assigned from Phase 1,
#             so app_store_apps succeed.
# ─────────────────────────────────────────────────────────────────────────────

UNASSIGNED_FILE="$FLEET_GITOPS_DIR/fleets/unassigned.yml"

# Create a temp directory (cleaned up on exit) for the stripped unassigned.yml.
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

# Strip app_store_apps from unassigned.yml for Phase 1.
# This removes the VPP dependency while keeping the team definition intact
# so Fleet can validate the "Unassigned" name in the VPP fleets list.
tmp_unassigned="$tmp_dir/unassigned.yml"
python3 - "$UNASSIGNED_FILE" "$tmp_unassigned" <<'PYEOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
data.pop('software', None)
with open(sys.argv[2], 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
PYEOF

# Build Phase 1 fleet args: all fleet files, replacing unassigned.yml with the
# stripped version so app_store_apps VPP validation is skipped in Phase 1.
phase1_fleet_args=()
for team_file in "$FLEET_GITOPS_DIR"/fleets/*.yml; do
  if [ -f "$team_file" ]; then
    if [[ "$(basename "$team_file")" == "unassigned.yml" ]]; then
      phase1_fleet_args+=(-f "$tmp_unassigned")
    else
      phase1_fleet_args+=(-f "$team_file")
    fi
  fi
done

# Phase 1: Apply global config + all teams (unassigned stripped of app_store_apps).
# Fleet clears then fully re-applies VPP at end of this run (including Unassigned).
$FLEETCTL gitops -f "$FLEET_GLOBAL_FILE" "${phase1_fleet_args[@]}" "${delete_args[@]}" --dry-run

if [ "$FLEET_DRY_RUN_ONLY" = true ]; then
  # Also dry-run Phase 2 to validate unassigned.yml
  $FLEETCTL gitops -f "$UNASSIGNED_FILE" --dry-run
  exit 0
fi

$FLEETCTL gitops -f "$FLEET_GLOBAL_FILE" "${phase1_fleet_args[@]}" "${delete_args[@]}"
# After Phase 1: VPP fleet assignments are correctly applied (including Unassigned).

# Phase 2: Apply unassigned.yml with full app_store_apps.
# No default.yml -> no "applied fleet config" -> VPP assignments preserved from Phase 1.
$FLEETCTL gitops -f "$UNASSIGNED_FILE" --dry-run
$FLEETCTL gitops -f "$UNASSIGNED_FILE"
