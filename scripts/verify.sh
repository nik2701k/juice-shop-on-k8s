#!/usr/bin/env bash
# Readiness and log-delivery verifier for the lab.
#
# Exits non-zero on any failure, so a deployment pipeline can gate on it. The
# marker is unique per run: a stale event cannot satisfy this check, which is
# the whole point of generating one instead of grepping for something fixed.
#
#   ./scripts/verify.sh              # full check
#   ./scripts/verify.sh --evidence   # also write a redacted transcript
#
# Requires the VPN to be up: nothing here is reachable from the internet.
set -uo pipefail

PROJECT="${PROJECT:-juiceshop-lab}"
REGION="${AWS_REGION:-us-east-1}"
MARKER_TIMEOUT="${MARKER_TIMEOUT:-180}"   # seconds to wait for log delivery
HTTP_TIMEOUT="${HTTP_TIMEOUT:-20}"
EVIDENCE_DIR="${EVIDENCE_DIR:-evidence}"

WRITE_EVIDENCE=0
[ "${1:-}" = "--evidence" ] && WRITE_EVIDENCE=1

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILURES=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
step() { printf '\n\033[1m%s\033[0m\n' "$1"; }

ssm_get() {
  aws ssm get-parameter --region "$REGION" --name "$1" --with-decryption \
    --query Parameter.Value --output text 2>/dev/null
}

# --------------------------------------------------------------------------
step "1. Preflight"
# --------------------------------------------------------------------------
for tool in aws kubectl curl python3; do
  command -v "$tool" >/dev/null 2>&1 || { fail "$tool is not installed"; }
done
[ "$FAILURES" -gt 0 ] && { echo; echo "preflight failed"; exit 2; }

aws sts get-caller-identity --region "$REGION" >/dev/null 2>&1 \
  && pass "AWS credentials usable" \
  || { fail "AWS credentials not usable"; exit 2; }

KUBECONFIG_FILE="$WORK/kubeconfig"
if ssm_get "/$PROJECT/k3s/kubeconfig" > "$KUBECONFIG_FILE" && [ -s "$KUBECONFIG_FILE" ]; then
  pass "kubeconfig retrieved from Parameter Store"
else
  fail "could not read /$PROJECT/k3s/kubeconfig"; exit 2
fi
export KUBECONFIG="$KUBECONFIG_FILE"

INDEXER_PW="$(ssm_get "/$PROJECT/wazuh/indexer-password")"
[ -n "$INDEXER_PW" ] && pass "indexer credentials retrieved" \
                     || { fail "could not read the indexer password"; exit 2; }

# --------------------------------------------------------------------------
step "2. Cluster readiness"
# --------------------------------------------------------------------------
# kubectl's own --request-timeout is used rather than timeout(1), which is
# not present on macOS by default.
if kubectl --request-timeout=30s get nodes >/dev/null 2>&1; then
  pass "Kubernetes API reachable (implies the VPN is up)"
else
  fail "cannot reach the Kubernetes API - is the VPN connected?"; exit 1
fi

for dep in juice-shop waf; do
  if kubectl -n lab rollout status "deploy/$dep" --timeout=110s >/dev/null 2>&1; then
    pass "deployment/$dep is available"
  else
    fail "deployment/$dep is not available"
  fi
done

WAF_IP="$(kubectl -n lab get svc waf -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)"
[ -n "$WAF_IP" ] && pass "WAF endpoint: $WAF_IP" || fail "WAF has no load balancer address"

# --------------------------------------------------------------------------
step "3. WAF behaviour"
# --------------------------------------------------------------------------
MARKER="VERIFY-$(python3 -c 'import uuid; print(uuid.uuid4())')"
echo "  marker: $MARKER"

ALLOWED_CODE="$(curl -s -o /dev/null -m "$HTTP_TIMEOUT" -w '%{http_code}' \
  "http://$WAF_IP/?marker=$MARKER" 2>/dev/null)"
[ "$ALLOWED_CODE" = "200" ] && pass "allowed request returned 200" \
                            || fail "allowed request returned $ALLOWED_CODE, expected 200"

# A single CRITICAL rule (942100) scores exactly the inbound threshold, so this
# blocks for one stated reason rather than an accumulation of noise.
BLOCKED_CODE="$(curl -s -o /dev/null -m "$HTTP_TIMEOUT" -w '%{http_code}' \
  --get --data-urlencode "q=' OR 1=1--" "http://$WAF_IP/" 2>/dev/null)"
[ "$BLOCKED_CODE" = "403" ] && pass "SQL injection blocked with 403" \
                            || fail "injection returned $BLOCKED_CODE, expected 403"

# Direct-origin bypass: the application Service is ClusterIP, so it must not be
# reachable even from inside the VPN.
JS_IP="$(kubectl -n lab get svc juice-shop -o jsonpath='{.spec.clusterIP}' 2>/dev/null)"
if curl -s -o /dev/null -m 6 "http://$JS_IP:3000/" 2>/dev/null; then
  fail "Juice Shop is reachable directly at $JS_IP:3000 - the WAF can be bypassed"
else
  pass "Juice Shop is not reachable except through the WAF"
fi

# --------------------------------------------------------------------------
step "4. Wazuh readiness"
# --------------------------------------------------------------------------
WAZUH_IP="$(python3 - <<'PY'
import subprocess
out = subprocess.run(["terraform","-chdir=terraform/environments/lab","output","-raw","wazuh_private_ip"],
                     capture_output=True, text=True)
print(out.stdout.strip() or "10.66.11.10")
PY
)"
HEALTH="$(curl -sk -u "admin:$INDEXER_PW" -m "$HTTP_TIMEOUT" \
  "https://$WAZUH_IP:9200/_cluster/health" 2>/dev/null \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])' 2>/dev/null)"
case "$HEALTH" in
  green|yellow) pass "indexer cluster health: $HEALTH" ;;
  *)            fail "indexer cluster health: ${HEALTH:-unreachable}" ;;
esac

# The shipped default must not still work. The literal below is Wazuh's
# published default, present so the check can prove it has been rotated -
# gitleaks:allow
DEFAULT_CODE="$(curl -sk -u "admin:SecretPassword" -m "$HTTP_TIMEOUT" \
  -o /dev/null -w '%{http_code}' "https://$WAZUH_IP:9200/_cluster/health" 2>/dev/null)"
[ "$DEFAULT_CODE" = "401" ] && pass "shipped default indexer password rejected" \
                            || fail "default password returned $DEFAULT_CODE, expected 401"

# --------------------------------------------------------------------------
step "5. Log delivery (the marker must reach the Indexer API)"
# --------------------------------------------------------------------------
DEADLINE=$(( $(date +%s) + MARKER_TIMEOUT ))
HITS=0
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  HITS="$(curl -sk -u "admin:$INDEXER_PW" -m "$HTTP_TIMEOUT" \
    "https://$WAZUH_IP:9200/wazuh-alerts-*/_search" \
    -H 'Content-Type: application/json' \
    -d "{\"query\":{\"query_string\":{\"query\":\"\\\"$MARKER\\\"\"}}}" 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["hits"]["total"]["value"])' 2>/dev/null || echo 0)"
  [ "${HITS:-0}" -gt 0 ] 2>/dev/null && break
  sleep 5
done

if [ "${HITS:-0}" -gt 0 ] 2>/dev/null; then
  ELAPSED=$(( MARKER_TIMEOUT - (DEADLINE - $(date +%s)) ))
  pass "marker found in the indexer after ~${ELAPSED}s"
  curl -sk -u "admin:$INDEXER_PW" -m "$HTTP_TIMEOUT" \
    "https://$WAZUH_IP:9200/wazuh-alerts-*/_search" \
    -H 'Content-Type: application/json' \
    -d "{\"query\":{\"query_string\":{\"query\":\"\\\"$MARKER\\\"\"}}}" 2>/dev/null \
    > "$WORK/hit.json"
  python3 - "$WORK/hit.json" <<'PY'
import json, sys
h = json.load(open(sys.argv[1]))["hits"]["hits"][0]["_source"]
print(f"        rule  : {h['rule']['id']} | {h['rule']['description']}")
print(f"        agent : {h['agent']['name']}")
print(f"        time  : {h['@timestamp']}")
PY
else
  fail "marker never reached the indexer within ${MARKER_TIMEOUT}s"
fi

# --------------------------------------------------------------------------
if [ "$WRITE_EVIDENCE" = "1" ]; then
  mkdir -p "$EVIDENCE_DIR"
  {
    echo "# Verifier run"
    echo
    echo '```'
    echo "marker      : $MARKER"
    echo "allowed     : HTTP $ALLOWED_CODE"
    echo "blocked     : HTTP $BLOCKED_CODE"
    echo "indexer     : $HEALTH"
    echo "default pw  : HTTP $DEFAULT_CODE (401 expected)"
    echo "marker hits : ${HITS:-0}"
    echo '```'
  } > "$EVIDENCE_DIR/verifier-run.md"
  echo
  echo "wrote $EVIDENCE_DIR/verifier-run.md"
fi

step "Result"
if [ "$FAILURES" -eq 0 ]; then
  echo "  all checks passed"
  exit 0
fi
echo "  $FAILURES check(s) failed"
exit 1
