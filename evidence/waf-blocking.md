# Evidence: Juice Shop behind a WAF

OWASP CRS 4.25.1 on ModSecurity 3.0.16, in front of Juice Shop v20.2.0.
Captured over the VPN. Public addresses are redacted; everything else verbatim.

## 1. One allowed request

```
$ curl -o /dev/null -w "%{http_code}" "http://<WAF>/?marker=VERIFY-4f3c1454-..."
200

$ curl -s http://<WAF>/ | grep -o '<title>[^<]*</title>'
<title>OWASP Juice Shop</title>
```

The application is served through the WAF, not merely reachable.

## 2. One deterministic blocked request

```
$ curl -o /dev/null -w "%{http_code}" --get --data-urlencode "q=' OR 1=1--" http://<WAF>/
403
```

A status code alone would not be deterministic, so here is the rule that
produced it, from the ModSecurity JSON audit record:

```
uri=/?q=%27+OR+1%3d1--    client=10.8.0.2    code=403
    id=942100  sev=2  SQL Injection Attack Detected via libinjection
    id=949110  sev=0  Inbound Anomaly Score Exceeded (Total Score: 5)
```

Rule **942100** contributes exactly 5 points; the inbound threshold is exactly
5. The block is caused by that single rule, not by an accumulation of unrelated
noise, so the same request blocks every time for the same stated reason.

Getting there required removing one rule. `920350` flags a numeric IP in the
Host header, which this lab always has because it is reached by address over
the VPN with no DNS name. It fired on every request and contributed 3 of the 5
points needed to block, leaving only 2 points of headroom — enough that one
extra WARNING on an ordinary request would have blocked it, and enough that the
demonstrated block would have depended partly on that noise. The exclusion is
in `k8s/waf/rules-configmap.yaml` with this reasoning recorded beside it.

A second, higher-scoring example, to show the threshold is not the only thing
doing the work:

```
uri=/?f=..%2f..%2f..%2fetc%2fpasswd    code=403
    id=930100  Path Traversal Attack (/../)
    id=930110  Path Traversal Attack (/../)
    id=930120  OS File Access Attempt
    id=932160  Remote Command Execution: Unix Shell Code Found
    id=949110  Inbound Anomaly Score Exceeded (Total Score: 33)
```

## 3. Direct-origin bypass is prevented

Three independent paths, all closed.

**The application has no address of its own.** Juice Shop's Service is
`ClusterIP`, so it is not routable from the VPN even though the whole VPC is:

```
$ nc -z -v 10.43.95.156 3000
failed: Operation timed out
```

**Nothing else in the cluster may reach it either.** A NetworkPolicy admits
only the WAF pod. The same request, from two different pods:

```
from an unrelated pod:   juice-shop:3000 -> 000   (blocked)
from the WAF pod:        juice-shop:3000 -> 200   (allowed)
```

**Nothing is published to the internet.** The app VM's security group permits
exactly one inbound flow from outside the VPC, and the WAF's port is not it:

```
-1     -1    10.66.11.0/24    NAT traffic forwarded from the private subnet
51820  udp   0.0.0.0/0        WireGuard tunnel

$ curl -m 8 -o /dev/null -w "%{http_code}" http://<APP_VM_PUBLIC_IP>/
000
```

The lab is therefore restricted to VPN peers, or to an allowlisted evaluator
address if `evaluator_cidrs` is set.

## 4. Two details that matter for the Wazuh stage

**Client addresses are real.** K3s's built-in load balancer source-NATs by
default, and the WAF logged `10.42.0.1` — the CNI gateway — as the client for
every request, which would have left Wazuh unable to attribute any event to a
source. With `externalTrafficPolicy: Local` on the Service, the same request
logs the true peer address:

```
before: "client_ip":"10.42.0.1"
after:  "client_ip":"10.8.0.2"
```

**Audit records are a usable size.** The image's default
`SecAuditLogParts ABIJDEFHZ` includes part E, the response body, making a
single record 11,412 bytes — mostly a verbatim copy of the page just served.
Dropping E brings it to 1,979 bytes, an 83% reduction, before any of it reaches
a 50 GB indexer volume:

```
before: 11412 bytes/record
after:   1979 bytes/record
```

Both the JSON audit log and the nginx access log are written to stdout, so the
Wazuh agent can collect them from the container log with no sidecar and no
shared volume. A unique marker sent in a request URI is present in that log,
which is the path the verifier will follow.
