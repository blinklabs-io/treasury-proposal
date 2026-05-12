#!/usr/bin/env bash
set -euo pipefail

# generate-report.sh - Generate a progress report from the template.
# Usage:
#   scripts/generate-report.sh              # Monthly report
#   scripts/generate-report.sh --quarterly  # Quarterly report (includes financials)
#
# Environment overrides:
#   MONTH   Two-digit month (01-12). Defaults to the current month.
#   YEAR    Four-digit year. Defaults to the current year.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="${REPO_ROOT}/docs/reports/TEMPLATE.md"
REPORTS_DIR="${REPO_ROOT}/docs/reports"

# ── Parse flags ──────────────────────────────────────────────────────────────

QUARTERLY=false
for arg in "$@"; do
    case "$arg" in
        --quarterly) QUARTERLY=true ;;
        -h|--help)
            echo "Usage: $(basename "$0") [--quarterly]"
            echo ""
            echo "  --quarterly   Generate a quarterly report (includes financial summary)"
            echo ""
            echo "Without --quarterly, generates a monthly report."
            exit 0
            ;;
        *)
            echo "Unknown argument: ${arg}" >&2
            exit 1
            ;;
    esac
done

# ── Verify template exists ──────────────────────────────────────────────────

if [[ ! -f "$TEMPLATE" ]]; then
    echo "Error: Report template not found at ${TEMPLATE}" >&2
    exit 1
fi

# ── Compute dates and filename ───────────────────────────────────────────────

YEAR="${YEAR:-$(date +%Y)}"
MONTH="${MONTH:-$(date +%m)}"

# Normalize MONTH to two digits and validate
if [[ ! "$MONTH" =~ ^[0-9]{1,2}$ ]]; then
    echo "Error: MONTH must be a number 1-12 (got: ${MONTH})" >&2
    exit 1
fi
MONTH="$(printf '%02d' "$((10#$MONTH))")"
if (( 10#$MONTH < 1 || 10#$MONTH > 12 )); then
    echo "Error: MONTH must be 1-12 (got: ${MONTH})" >&2
    exit 1
fi

if [[ ! "$YEAR" =~ ^[0-9]{4}$ ]]; then
    echo "Error: YEAR must be a 4-digit year (got: ${YEAR})" >&2
    exit 1
fi

MONTH_NAME="$(date -d "${YEAR}-${MONTH}-01" +%B)"

if [[ "$QUARTERLY" == true ]]; then
    # Determine quarter from current month
    case "$MONTH" in
        01|02|03) QUARTER=1; Q_START="January";  Q_END="March" ;;
        04|05|06) QUARTER=2; Q_START="April";    Q_END="June" ;;
        07|08|09) QUARTER=3; Q_START="July";     Q_END="September" ;;
        10|11|12) QUARTER=4; Q_START="October";  Q_END="December" ;;
    esac
    REPORT_FILE="${REPORTS_DIR}/${YEAR}-Q${QUARTER}-report.md"
    PERIOD="${Q_START} - ${Q_END} ${YEAR}"
    PERIOD_TITLE="Q${QUARTER} ${YEAR}"
    START_DATE="${Q_START} 1, ${YEAR}"
    END_DATE="${Q_END} ${YEAR}"
    REPORT_TYPE="Quarterly"
else
    REPORT_FILE="${REPORTS_DIR}/${YEAR}-${MONTH}-report.md"
    PERIOD="${MONTH_NAME} ${YEAR}"
    PERIOD_TITLE="${MONTH_NAME} ${YEAR}"
    START_DATE="${MONTH_NAME} 1, ${YEAR}"
    END_DATE="${MONTH_NAME} $(date -d "${YEAR}-${MONTH}-01 +1 month -1 day" +%d 2>/dev/null || date -d "last day of ${MONTH_NAME} ${YEAR}" +%d 2>/dev/null || echo "??"), ${YEAR}"
    REPORT_TYPE="Monthly"
fi

# ── Check for existing report ────────────────────────────────────────────────

if [[ -f "$REPORT_FILE" ]]; then
    echo "Warning: ${REPORT_FILE} already exists." >&2
    read -rp "Overwrite? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted." >&2
        exit 1
    fi
fi

# ── Generate from template ──────────────────────────────────────────────────

cp "$TEMPLATE" "$REPORT_FILE"

# Fill in placeholders
sed -i "s/PERIOD_PLACEHOLDER/${PERIOD_TITLE}/g" "$REPORT_FILE"
sed -i "s/START_DATE_PLACEHOLDER/${START_DATE}/g" "$REPORT_FILE"
sed -i "s/END_DATE_PLACEHOLDER/${END_DATE}/g" "$REPORT_FILE"
sed -i "s/REPORT_TYPE_PLACEHOLDER/${REPORT_TYPE}/g" "$REPORT_FILE"

# For monthly reports, strip the financial summary section
if [[ "$QUARTERLY" == false ]]; then
    # Remove the Financial Summary section (from "## Financial Summary" to the
    # next "##" heading), keeping the rest of the document intact.
    sed -i '/^## Financial Summary$/,/^## /{/^## Financial Summary$/d;/^## /!d}' "$REPORT_FILE"
fi

echo "Report generated: ${REPORT_FILE}"

# ── Open in editor if available ──────────────────────────────────────────────

if [[ -n "${EDITOR:-}" ]]; then
    echo "Opening in \$EDITOR (${EDITOR})..."
    exec "$EDITOR" "$REPORT_FILE"
else
    echo "Set \$EDITOR to open the report automatically."
fi
