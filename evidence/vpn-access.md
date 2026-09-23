# Evidence: private access over WireGuard

Captured from an operator laptop with the lab's `client-1` peer config, fetched
from SSM Parameter Store. Public addresses, peer keys, and the operator's own
ISP address are redacted; everything else is verbatim.

## 1. The tunnel is the only route to the lab

```
$ netstat -rn -f inet | grep '^10\.'
10.8/24            utun5              USc                 utun5
10.8.0.2           10.8.0.2           UH                  utun5
10.66/16           utun5              USc                 utun5

$ route -n get 10.66.11.189 | grep interface
  interface: utun5
```

Both the VPN pool and the whole VPC resolve to the WireGuard interface.

## 2. Handshake and liveness

```
$ ping -c 3 10.8.0.1
3 packets transmitted, 3 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 234.392/234.585/234.913/0.233 ms
```

## 3. The host on the far side is ours, not a coincidence

Reaching the app VM's private address over the tunnel returns an SSH banner:

```
$ nc 10.66.1.81 22 </dev/null | head -1
SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.19
```

The same host, queried independently through SSM Session Manager, reports the
identical build and confirms it holds both addresses:

```
OpenSSH_9.6p1 Ubuntu-3ubuntu13.19, OpenSSL 3.0.13 30 Jan 2024
10.66.1.81 10.8.0.1
```

This matters because an earlier run of this test passed against the *wrong*
machine: the operator's corporate VPN already owned a route for the VPC's
previous CIDR, so the probes silently went there instead. Matching the banner
against an out-of-band SSM query is what distinguishes a real result from that
false positive.

## 4. Security groups are enforced across the tunnel

The Wazuh VM has no public address and no service listening yet, so the two
outcomes below differ only by whether its security group permits the port.

```
$ nc -z -v 10.66.11.189 1514     # port IS in the Wazuh SG
failed: Connection refused

$ nc -z -v 10.66.11.189 22       # port is NOT in the Wazuh SG
failed: Operation timed out
```

**Refused** means the packet crossed the tunnel, was masqueraded to the app
VM's private address, satisfied the Wazuh security group, reached the host, and
was rejected only because nothing is listening. **Timed out** on a port the
group does not list means it was dropped before arrival. The contrast proves
both that the path works and that the firewall is doing its job.

## 5. Split tunnel: ordinary traffic is untouched

```
before tunnel:  <OPERATOR_ISP_ADDRESS>
with tunnel up: <OPERATOR_ISP_ADDRESS>   (unchanged)
```

`AllowedIPs` covers only `10.66.0.0/16` and `10.8.0.0/24`, so the lab neither
routes nor observes the operator's normal internet traffic.

## 6. Revoked keys stop working

After the app VM was replaced, its keys regenerated. The still-running tunnel,
holding the previous peer key, immediately went dark:

```
$ ping -c 3 10.8.0.1
3 packets transmitted, 0 packets received, 100.0% packet loss
```

Unauthenticated peers get no reply at all, which is also why the single
internet-facing port is invisible to a scanner.
