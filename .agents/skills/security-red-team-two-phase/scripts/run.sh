#!/usr/bin/env bash
set -euo pipefail

PHASE="${1:-}"
TARGET_OR_REPORT="${2:-}"
SCOPE_OR_APPROVAL="${3:-}"
REPORT_DIR="${SECURITY_REPORT_DIR:-security-reports}"

usage() {
  cat >&2 <<'EOF'
Usage:
  run.sh analyze <target> [scope-or-goal]
  run.sh fix <analysis-report.md> --approve

ANALYZE is read/test-only. FIX requires an existing report and the literal --approve.
EOF
}

[[ -n "$PHASE" && -n "$TARGET_OR_REPORT" ]] || { usage; exit 2; }

case "$PHASE" in
  analyze)
    mkdir -p "$REPORT_DIR"
    timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
    report="$REPORT_DIR/security-analysis-${timestamp}.md"
    json="$REPORT_DIR/security-analysis-${timestamp}.json"
    scope="${SCOPE_OR_APPROVAL:-authorized target; scope must be confirmed by the agent}"

    cat > "$report" <<EOF
# Security Analysis — ${timestamp}

- Target: ${TARGET_OR_REPORT}
- Scope: ${scope}
- Phase: ANALYZE ONLY
- Project files changed by runner: NO

## Required agent work

1. Confirm authorization and scope.
2. Map assets, entry points and trust boundaries.
3. Execute safe, non-destructive, evidence-backed tests.
4. Add findings using the format from SKILL.md.
5. Do not patch files in this phase.

## Status

ANALYSIS_PENDING
EOF

    cat > "$json" <<EOF
{
  "phase": "ANALYZE",
  "target": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$TARGET_OR_REPORT"),
  "scope": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$scope"),
  "report": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$report"),
  "status": "ANALYSIS_PENDING",
  "files_changed": false
}
EOF
    sha256sum "$report" | tee "${report}.sha256"
    printf 'ANALYSIS_REPORT=%s\nANALYSIS_JSON=%s\n' "$report" "$json"
    ;;

  fix)
    [[ "$SCOPE_OR_APPROVAL" == "--approve" ]] || {
      echo "BLOCKED: fix requires the literal --approve after a concrete analysis report." >&2
      exit 3
    }
    [[ -f "$TARGET_OR_REPORT" ]] || {
      echo "BLOCKED: analysis report does not exist: $TARGET_OR_REPORT" >&2
      exit 4
    }
    grep -qE '^# Security Analysis|^## Findings' "$TARGET_OR_REPORT" || {
      echo "BLOCKED: report is not a recognized security analysis report." >&2
      exit 5
    }
    echo "FIX_PHASE_AUTHORIZED"
    echo "REPORT=$TARGET_OR_REPORT"
    echo "The agent may now apply only the report's approved minimal patches, then run negative and positive regression tests."
    ;;
  *)
    usage
    exit 2
    ;;
esac
