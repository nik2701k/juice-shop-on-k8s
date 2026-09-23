#!/usr/bin/env bash
# Waits for an SSM command, echoes its output, and exits non-zero if it failed.
# Without this a send-command returns immediately and the job goes green no
# matter what happened on the instance.
set -euo pipefail
CMD="$1"; INSTANCE="$2"; DEADLINE=$(( $(date +%s) + 900 ))

while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  STATUS="$(aws ssm get-command-invocation --command-id "$CMD" --instance-id "$INSTANCE" \
    --query Status --output text 2>/dev/null || echo Pending)"
  case "$STATUS" in
    Success) break ;;
    Failed|Cancelled|TimedOut) break ;;
  esac
  sleep 10
done

aws ssm get-command-invocation --command-id "$CMD" --instance-id "$INSTANCE" \
  --query StandardOutputContent --output text || true
aws ssm get-command-invocation --command-id "$CMD" --instance-id "$INSTANCE" \
  --query StandardErrorContent --output text >&2 || true

[ "${STATUS:-}" = "Success" ] || { echo "SSM command $STATUS" >&2; exit 1; }
