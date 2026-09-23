# Evidence: a fresh event reaching Wazuh

Full chain: request through the WAF, collected by the agent, evaluated by the
manager, queried back out of the Indexer API. Addresses are private; no
redaction beyond the marker being unique per run.

## Agent enrolled automatically

```
$ /var/ossec/bin/agent_control -l
   ID: 000, Name: wazuh.manager (server), IP: 127.0.0.1, Active/Local
   ID: 001, Name: ip-10-66-1-161, IP: any, Active
```

Enrolment is password-protected; the manager mints the password, publishes it
to Parameter Store, and the agent reads it from there. It is never written into
any file in this repo.

## A unique marker, end to end

```
marker : VERIFY-bfbf7bc9-ab49-4873-81a0-653f0d0dec33
allowed: HTTP 200
```

Queried straight from the Indexer API:

```
index : wazuh-alerts-4.x-2026.09.23
rule  : 100100 | Lab verifier marker observed in the WAF access log
agent : ip-10-66-1-161
time  : 2026-09-23T04:14:27.500Z
```

Found 20 seconds after the request. The marker is generated per run, so this
cannot be satisfied by a stale event.

## The WAF's own decisions are alerts too

A blocked request surfaces as a security event, not merely a 403:

```
Rule: 31164 (level 6) -> 'SQL injection attempt.'
Src IP: 10.8.0.2
... "GET /?q=%27+OR+1%3d1-- HTTP/1.1" 403 146
```

`Src IP` is the real VPN peer, which is only true because the WAF Service sets
`externalTrafficPolicy: Local`; by default K3s source-NATs and every event
would be attributed to the CNI gateway.

## Why the rule needs `if_sid`

Wazuh emits one alert per event, choosing the single best-matching rule. A
bare top-level `<match>VERIFY-</match>` never fired, because the built-in web
access-log rule had already matched the same line and won. Declaring the rule a
child of `31100` places it inside that rule's subtree, where it is evaluated
and wins. This was diagnosed by confirming events were arriving and alerting
normally while the marker specifically produced nothing.
