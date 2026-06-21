#!/usr/bin/env bash
# =============================================================================
# trigger-jenkins-pipeline.sh
# =============================================================================
# Triggers a Jenkins pipeline from the terminal and streams the full console
# output — no browser required.
#
# Prerequisites:
#   1. Java installed (for jenkins-cli.jar)
#   2. Jenkins running on port 8082
#   3. A Jenkins API token (see instructions below)
#
# ---------------------------------------------------------------------------
# HOW TO GENERATE A JENKINS API TOKEN (port 8082)
# ---------------------------------------------------------------------------
#   1. Open:  http://localhost:8082
#   2. Log in as: admin
#   3. Click your username (top-right) -> Configure
#   4. Scroll to "API Token" -> "Add new Token"
#   5. Give it a name (e.g. "cli-token") -> Generate
#   6. COPY the token immediately (it won't be shown again)
#   7. Export it:
#        export JENKINS_TOKEN="your-copied-token"
#
# ---------------------------------------------------------------------------
# Usage:
#   # Simplest form (job name as first argument):
#   export JENKINS_TOKEN="your-token"
#   ./scripts/trigger-jenkins-pipeline.sh "Shopping-Cart"
#
#   # With all options:
#   ./scripts/trigger-jenkins-pipeline.sh -j "Shopping-Cart" -u admin -p "$JENKINS_TOKEN"
#
#   # One-liner equivalent (no wrapper needed):
#   java -jar jenkins-cli.jar -s http://localhost:8082/ -auth admin:TOKEN \
#     build "Shopping-Cart" -f -s -v
#
# Flags:
#   -f  Wait until the build finishes
#   -s  Sync console output (stream logs to terminal)
#   -v  Verbose mode
# =============================================================================

set -euo pipefail

# Load local config if present (scripts/jenkins.local.env is gitignored)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/jenkins.local.env" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/jenkins.local.env"
fi

# Defaults
JENKINS_URL="${JENKINS_URL:-http://localhost:8082}"
JENKINS_USER="${JENKINS_USER:-admin}"
JENKINS_TOKEN="${JENKINS_TOKEN:-}"
JOB_NAME="${JOB_NAME:-pipeline}"
CLI_JAR="${CLI_JAR:-./jenkins-cli.jar}"

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage:
  $(basename "$0") [JOB_NAME]
  $(basename "$0") -j JOB_NAME [-u USER] [-p TOKEN] [-s URL] [-f JAR]

Arguments:
  JOB_NAME          Jenkins pipeline job name (positional or -j flag)

Options:
  -s URL            Jenkins URL         (default: http://localhost:8082)
  -j JOB_NAME       Pipeline job name   (default: Shopping-Cart)
  -u USER           Jenkins username    (default: admin)
  -p TOKEN          Jenkins API token   (or set JENKINS_TOKEN env var)
  -f JAR            Path to jenkins-cli.jar (default: ./jenkins-cli.jar)
  -h                Show this help

Generate API token:
  http://localhost:8082/user/admin/configure -> API Token -> Add new Token

Examples:
  export JENKINS_TOKEN="abc123"
  $(basename "$0") "Shopping-Cart"
  $(basename "$0") -j "Shopping-Cart" -p "\$JENKINS_TOKEN"
EOF
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while getopts "s:j:u:p:f:h" opt; do
  case "$opt" in
    s) JENKINS_URL="$OPTARG" ;;
    j) JOB_NAME="$OPTARG" ;;
    u) JENKINS_USER="$OPTARG" ;;
    p) JENKINS_TOKEN="$OPTARG" ;;
    f) CLI_JAR="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

# Accept job name as first positional argument
if [[ $# -gt 0 ]]; then
  JOB_NAME="$1"
fi

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------
if [[ -z "${JENKINS_TOKEN}" ]]; then
  echo "ERROR: Jenkins API token is required." >&2
  echo "" >&2
  echo "  export JENKINS_TOKEN=\"your-token\"" >&2
  echo "  OR: $(basename "$0") -p your-token \"${JOB_NAME}\"" >&2
  echo "" >&2
  echo "Generate token at: ${JENKINS_URL}/user/${JENKINS_USER}/configure" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Download jenkins-cli.jar if not present
# ---------------------------------------------------------------------------
if [[ ! -f "${CLI_JAR}" ]]; then
  echo ">>> Downloading jenkins-cli.jar from ${JENKINS_URL} ..."
  curl -fsSL -o "${CLI_JAR}" "${JENKINS_URL}/jnlpJars/jenkins-cli.jar"
  echo ">>> Saved to ${CLI_JAR}"
fi

# ---------------------------------------------------------------------------
# Trigger build and stream logs
# ---------------------------------------------------------------------------
AUTH="${JENKINS_USER}:${JENKINS_TOKEN}"

echo "============================================================"
echo "  Jenkins Pipeline Trigger"
echo "  URL     : ${JENKINS_URL}"
echo "  User    : ${JENKINS_USER}"
echo "  Job     : ${JOB_NAME}"
echo "  Mode    : wait + stream logs (-f -s -v)"
echo "============================================================"
echo ""

java -jar "${CLI_JAR}" \
  -s "${JENKINS_URL}/" \
  -auth "${AUTH}" \
  build "${JOB_NAME}" \
  -f -s -v

EXIT_CODE=$?

echo ""
if [[ ${EXIT_CODE} -eq 0 ]]; then
  echo ">>> BUILD SUCCESS: ${JOB_NAME}"
else
  echo ">>> BUILD FAILED: ${JOB_NAME} (exit code ${EXIT_CODE})"
  echo ">>> Check diagnostics output above for docker logs."
fi

exit "${EXIT_CODE}"
