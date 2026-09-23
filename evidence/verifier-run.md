# Evidence: verifier run

`./scripts/verify.sh` — readiness, WAF behaviour, and log delivery. The marker
is generated per run, so a stale event cannot satisfy it.

## Passing run (exit 0)

```
1. Preflight
  PASS  AWS credentials usable
  PASS  kubeconfig retrieved from Parameter Store
  PASS  indexer credentials retrieved

2. Cluster readiness
  PASS  Kubernetes API reachable (implies the VPN is up)
  PASS  deployment/juice-shop is available
  PASS  deployment/waf is available
  PASS  WAF endpoint: 10.66.1.161

3. WAF behaviour
  marker: VERIFY-4e4807da-b887-4c8e-80bc-2e58813e00d0
  PASS  allowed request returned 200
  PASS  SQL injection blocked with 403
  PASS  Juice Shop is not reachable except through the WAF

4. Wazuh readiness
  PASS  indexer cluster health: green
  PASS  shipped default indexer password rejected

5. Log delivery (the marker must reach the Indexer API)
  PASS  marker found in the indexer after ~1s
        rule  : 100100 | Lab verifier marker observed in the WAF access log
        agent : ip-10-66-1-161
        time  : 2026-09-23T04:18:21.523Z

Result
  all checks passed
```

## The failure paths, exercised

A gate that cannot fail is not a gate, so both exit codes were produced
deliberately rather than assumed.

```
$ PROJECT=does-not-exist ./scripts/verify.sh
exit=2            # preflight: secrets unreadable, nothing was attempted

$ MARKER_TIMEOUT=0 ./scripts/verify.sh
  FAIL  marker never reached the indexer within 0s
  1 check(s) failed
exit=1            # readiness passed, log delivery did not
```

Exit 2 means the check could not run; exit 1 means it ran and something
failed. A pipeline can therefore distinguish "broken runner" from "broken
deployment".
