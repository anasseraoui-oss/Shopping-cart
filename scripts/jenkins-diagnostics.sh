#!/usr/bin/env bash
# =============================================================================
# jenkins-diagnostics.sh
# =============================================================================
# Called automatically by the Jenkinsfile when:
#   - Health Check fails after 120 seconds of polling
#   - Any pipeline stage fails (post { failure { ... } } block)
#
# Dumps deployment diagnostics to the Jenkins console so you can see
# Java/Spring Boot errors without opening the browser.
#
# Environment variables (set by Jenkinsfile, or use defaults):
#   TARGET_NODE     - Ansible target container  (default: ansible-node1)
#   APP_NAME        - Application container     (default: shopping-cart)
#   ANSIBLE_NETWORK - Docker bridge network     (default: ansible-network)
#   LOG_TAIL        - Number of log lines       (default: 50)
#
# Usage (manual):
#   chmod +x scripts/jenkins-diagnostics.sh
#   TARGET_NODE=ansible-node1 APP_NAME=shopping-cart ./scripts/jenkins-diagnostics.sh
# =============================================================================

set -u

TARGET_NODE="${TARGET_NODE:-ansible-node1}"
APP_NAME="${APP_NAME:-shopping-cart}"
ANSIBLE_NETWORK="${ANSIBLE_NETWORK:-ansible-network}"
LOG_TAIL="${LOG_TAIL:-50}"

echo ""
echo "============================================================"
echo "  DEPLOYMENT DIAGNOSTICS"
echo "  Target node : ${TARGET_NODE}"
echo "  App container: ${APP_NAME}"
echo "  Network     : ${ANSIBLE_NETWORK}"
echo "  Log tail    : ${LOG_TAIL} lines"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# 1. Container status (running / exited / crash loop)
# ---------------------------------------------------------------------------
echo "=== [1/5] docker ps -a --filter name=${APP_NAME} ==="
docker exec "${TARGET_NODE}" docker ps -a --filter "name=${APP_NAME}" 2>&1 || \
  echo "  WARNING: Could not run docker ps on ${TARGET_NODE}"
echo ""

# ---------------------------------------------------------------------------
# 2. Container inspect (exit code, error message, restart count)
# ---------------------------------------------------------------------------
echo "=== [2/5] docker inspect ${APP_NAME} ==="
docker exec "${TARGET_NODE}" docker inspect "${APP_NAME}" \
  --format '  Status     : {{.State.Status}}
  Running    : {{.State.Running}}
  ExitCode   : {{.State.ExitCode}}
  Error      : {{.State.Error}}
  Restarts   : {{.RestartCount}}
  StartedAt  : {{.State.StartedAt}}
  NetworkMode: {{.HostConfig.NetworkMode}}' \
  2>&1 || echo "  WARNING: Container '${APP_NAME}' not found or inspect failed"
echo ""

# ---------------------------------------------------------------------------
# 3. Container logs (Java / Spring Boot stack traces)
# ---------------------------------------------------------------------------
echo "=== [3/5] docker logs --tail ${LOG_TAIL} ${APP_NAME} ==="
docker exec "${TARGET_NODE}" docker logs --tail "${LOG_TAIL}" "${APP_NAME}" 2>&1 || \
  echo "  WARNING: Could not fetch logs for '${APP_NAME}'"
echo ""

# ---------------------------------------------------------------------------
# 4. Network connectivity on ansible-network
# ---------------------------------------------------------------------------
echo "=== [4/5] ansible-network connectivity ==="

echo "  -- Network exists? --"
if docker network inspect "${ANSIBLE_NETWORK}" >/dev/null 2>&1; then
  echo "  YES: ${ANSIBLE_NETWORK} exists"
else
  echo "  NO: ${ANSIBLE_NETWORK} does NOT exist - run: docker network create ${ANSIBLE_NETWORK}"
fi

echo ""
echo "  -- Containers attached to ${ANSIBLE_NETWORK} --"
docker network inspect "${ANSIBLE_NETWORK}" \
  --format '{{range .Containers}}  - {{.Name}} (IPv4: {{.IPv4Address}}){{"\n"}}{{end}}' \
  2>&1 || echo "  WARNING: Could not inspect network"

echo ""
echo "  -- Can ${TARGET_NODE} resolve ${APP_NAME} via DNS? --"
docker exec "${TARGET_NODE}" sh -c \
  "getent hosts ${APP_NAME} 2>/dev/null || nslookup ${APP_NAME} 2>/dev/null || echo '  DNS resolution FAILED for ${APP_NAME}'" \
  2>&1 || true

echo ""
echo "  -- Ping port 8070 from ${TARGET_NODE} (HTTP probe) --"
docker exec "${TARGET_NODE}" sh -c "
  for url in \
    http://${APP_NAME}:8070/home \
    http://${APP_NAME}:8070/health \
    http://localhost:8070/home \
    http://localhost:8070/health
  do
    code=\$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 \"\$url\" 2>/dev/null || echo 000)
    echo \"  \$url -> HTTP \$code\"
  done
" 2>&1 || echo "  WARNING: HTTP probe failed"

# ---------------------------------------------------------------------------
# 5. Jenkins container network attachment check
# ---------------------------------------------------------------------------
echo ""
echo "=== [5/5] Jenkins container network check ==="
JENKINS_CID="$(hostname 2>/dev/null || echo unknown)"
echo "  Jenkins container ID/hostname: ${JENKINS_CID}"
docker network inspect "${ANSIBLE_NETWORK}" \
  --format '{{range .Containers}}{{if eq .Name "'"${JENKINS_CID}"'"}}{{.Name}} is attached ({{.IPv4Address}}){{end}}{{end}}' \
  2>/dev/null || true
docker network inspect "${ANSIBLE_NETWORK}" \
  --format '{{range .Containers}}{{if eq .Name "'"${TARGET_NODE}"'"}}{{.Name}} is attached ({{.IPv4Address}}){{end}}{{end}}' \
  2>/dev/null || true

echo ""
echo "============================================================"
echo "  END DIAGNOSTICS"
echo "============================================================"
echo ""
