#!/usr/bin/env bash
set -euo pipefail

URL="${1:-}"
GOAL="${2:-}"
PROJECT_ID="${3:-}"

if [[ -z "$URL" ]]; then
  echo "Usage: run.sh <url> [goal] [project-id]" >&2
  exit 2
fi

GOAL="${GOAL:-Erreiche das wichtigste End-to-End-Nutzerziel und prüfe die Meilensteine von Start bis Abschluss.}"

command -v scoutqa >/dev/null 2>&1 || {
  echo "ERROR: scoutqa CLI is not installed or not on PATH" >&2
  exit 127
}

BASE_PROMPT="""
Act as a goal-driven exploratory test agent.
Target: ${URL}
Primary goal: ${GOAL}

Use milestone order:
M0 boot/reachability/initialization;
M1 input/navigation/basic control;
M2 core goal and first meaningful progress;
M3 state transition, persistence, reload and resume;
M4 invalid input, interruption, timeout, recovery and boundary cases;
M5 end-to-end completion, performance and regression.

Think like a real user pursuing the goal. Do not equate a clickable control or a loaded script with success.
For each reached milestone record PASS, PARTIAL, BLOCKED or FAIL and the evidence.
Stop later claims when an earlier milestone is blocked. Report reproducible findings with preconditions, actions, expected, observed, impact and evidence.
"""

run_case() {
  local label="$1"
  local focus="$2"
  local prompt="${BASE_PROMPT}

Focus area: ${focus}
Return a structured milestone report and only evidence-backed findings."
  local args=(--url "$URL" --prompt "$prompt")
  [[ -n "$PROJECT_ID" ]] && args+=(--project-id "$PROJECT_ID")
  echo "=== START ${label} ===" >&2
  scoutqa "${args[@]}"
}

# Independent scopes are launched in parallel so the automation gets broad coverage.
run_case "CORE_GOAL" "Normal and alternative path to the primary user goal, including visible output and completion criteria." >"${TMPDIR:-/tmp}/goal-driven-core.$$" 2>&1 &
P1=$!
run_case "RECOVERY" "Negative paths, interruption, reload/resume, invalid inputs, timeouts, missing resources and recovery." >"${TMPDIR:-/tmp}/goal-driven-recovery.$$" 2>&1 &
P2=$!
run_case "UX_RUNTIME" "Accessibility, keyboard/touch, responsive behavior, console/network errors, loading states and runtime performance." >"${TMPDIR:-/tmp}/goal-driven-ux.$$" 2>&1 &
P3=$!

status=0
wait "$P1" || status=1
wait "$P2" || status=1
wait "$P3" || status=1

for f in "${TMPDIR:-/tmp}/goal-driven-core.$$" "${TMPDIR:-/tmp}/goal-driven-recovery.$$" "${TMPDIR:-/tmp}/goal-driven-ux.$$"; do
  cat "$f"
  rm -f "$f"
done

exit "$status"
