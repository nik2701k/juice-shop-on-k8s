# Juice Shop on K8s — Wazuh / WAF / VPN lab

Terraform-driven security lab on AWS: OWASP Juice Shop on K3s behind a
ModSecurity WAF, reachable only over WireGuard, with a private Wazuh stack
collecting and indexing the ingress logs.

**Status: phase 1 of 5 — network layer applied and verified.** See
[Roadmap](#roadmap) for what is built and what is not.

---

## Architecture

```
                    internet
                        │
                        │  udp/51820 — the ONLY port open to the world
                        ▼
┌───────────────────────────────────────────── VPC 10.0.0.0/16 ──┐
│                                                                 │
│  public subnet 10.0.1.0/24          private subnet 10.0.11.0/24 │
│  ┌──────────────────────────┐       ┌─────────────────────────┐ │
│  │ app VM                   │       │ wazuh VM                │ │
│  │  • WireGuard endpoint    │       │  • wazuh manager        │ │
│  │  • NAT for private subnet│──────▶│  • wazuh indexer        │ │
│  │  • K3s                   │  masq │  • wazuh dashboard      │ │
│  │    └ ingress-nginx + WAF │       │  • EBS data volume      │ │
│  │       └ juice-shop (CIP) │       │  no public IP, ever     │ │
│  │  • wazuh agent           │       └─────────────────────────┘ │
│  └──────────────────────────┘                                   │
│         │ IGW                        (no route to the IGW)      │
└─────────┼───────────────────────────────────────────────────────┘
          ▼
       internet
```

Traffic to Juice Shop can only arrive through the WAF, because the Juice Shop
Service is `ClusterIP` — it has no node port and no load balancer, so there is
no address that reaches it except through ingress-nginx.

---

## Design decisions

Every choice below traded something away. The reasoning matters more than the
result, so it is recorded here rather than lost in commit messages.

### Cost decisions

The lab has to fit inside trial credits, so each avoided managed service is
listed with what it would have cost in `us-east-1`.

| Decision | Alternative rejected | Why | Saved / mo |
|---|---|---|---|
| App VM doubles as the NAT instance | NAT Gateway | The app VM already runs `ip_forward` and masquerades for WireGuard peers. Covering the private subnet is two more iptables rules on a box already doing that job. | **$32.40** + $0.045/GB |
| K3s on a VM | EKS | The task names K3s as the preference. EKS bills the control plane before a single node exists. | **$73.00** |
| ingress-nginx with ModSecurity in-cluster | ALB + AWS WAF | ModSecurity + OWASP CRS is free, and one component covers ingress, WAF, and the access log Wazuh consumes. | **$16.20** + **~$6** |
| NAT hop for SSM traffic | 3 × SSM interface VPC endpoints | Endpoints are billed per hour per AZ; the NAT hop is already there. | **~$21.60** |
| Native S3 state locking (`use_lockfile`) | DynamoDB lock table | Terraform ≥ 1.10 locks in S3 directly. One less resource to create, tag, and pay for. | ~$0 (one less resource) |
| Single AZ | Multi-AZ | HA is explicitly optional for this lab. A second AZ doubles subnets and adds cross-AZ data charges for no assessable benefit. | cross-AZ transfer |
| Self-signed TLS | ACM + Route53 domain | The lab is private. No public domain is needed, and none is available. | domain cost |

**Roughly $149/month of managed-service spend avoided** versus the same
architecture built the conventional enterprise way.

### Security decisions

| Decision | Why |
|---|---|
| Wazuh VM has **no public IP and no route to the IGW** | It holds the security telemetry. Unreachable by construction beats unreachable by firewall rule. |
| `map_public_ip_on_launch = false` on the *public* subnet too | Public addressing is granted explicitly per instance via an EIP. A future instance cannot become internet-facing by forgetting a flag. |
| Private route table ships with **no default route** | The NAT hop is an instance ENI owned by the compute layer. Until it exists the subnet is fail-closed, which is the correct intermediate state. |
| Every Wazuh ingress rule is **security-group-referenced**, not CIDR | The rule stays correct if addresses change, and it cannot accidentally widen to a subnet. |
| Default SG is managed and left **empty** | AWS ships it with an allow-all-from-self rule. Managing it empty makes accidental use harmless and keeps CIS/Trivy checks green. |
| `0.0.0.0/0` is **rejected at plan time** for `admin_cidrs` / `evaluator_cidrs` | A `validation` block fails the plan. Cheaper than catching it in review, and far cheaper than catching it in production. |
| SSH defaults to **closed**; SSM Session Manager is the access path | No key pair to distribute, lose, or commit. Port 22 opens only if `admin_cidrs` is set deliberately. |
| Juice Shop Service is `ClusterIP` | Prevents direct-origin bypass structurally. There is no address that skips the WAF. |
| State bucket denies `aws:SecureTransport=false` | Encryption at rest is not enough; plaintext requests are rejected outright. |
| State bucket versioning enabled | This is the control that makes a truncated or corrupted state file recoverable. |

### Reliability decisions

| Decision | Why |
|---|---|
| Wazuh compose supervised by a **systemd unit**, not a bare `docker compose up -d` | Survives reboot, not just container crash. K3s workloads already get this from the kubelet. |
| `vm.max_map_count` persisted to `/etc/sysctl.d/` | Set live by cloud-init it works on first apply, then the indexer refuses to start after the first reboot. Classic silent failure. |
| Wazuh data on a **separate EBS volume** with `prevent_destroy`, `nofail` in fstab | Satisfies "reruns must preserve data". Miss the fstab entry and Wazuh returns with an empty data dir, which looks exactly like a crash. |

---

## Repository layout

```
terraform/
├── environments/lab/           # root module: provider, backend, wiring, tfvars
│   ├── lab.tfvars              # committed — the shape of the lab, not secrets
│   ├── local.auto.tfvars.example  # copy to local.auto.tfvars for operator IPs
│   └── backend.hcl.example     # state bucket config + one-time creation commands
└── modules/
    ├── network/                # VPC, subnets, IGW, route tables, default-SG lockdown
    └── security-groups/        # app SG + wazuh SG
```

Standard `modules/` + `environments/` split. Modules declare
`required_providers` but never a `provider` block, every variable carries a
description, and every module has an `outputs.tf`. Adding a second environment
is a new directory, not a rewrite.

### Variable handling

Infrastructure-shape variables have **no defaults** in the root module, so
`lab.tfvars` is the only place a value can come from and a default can never
silently disagree with the tfvars file. Consequence: `plan` and `apply`
require `-var-file=lab.tfvars`.

Operator addresses live in `local.auto.tfvars`, which is gitignored and
auto-loaded, so a home IP never reaches the repo or the redacted evidence.

---

## Prerequisites

- Terraform ≥ 1.10 (native S3 state locking)
- AWS CLI v2 with a configured profile
- An S3 state bucket — see `backend.hcl.example` for the one-time commands

## Usage

```bash
cp terraform/environments/lab/backend.hcl.example terraform/environments/lab/backend.hcl
# edit bucket/profile, then:

terraform -chdir=terraform/environments/lab init -backend-config=backend.hcl
terraform -chdir=terraform/environments/lab validate
terraform -chdir=terraform/environments/lab plan    -var-file=lab.tfvars
terraform -chdir=terraform/environments/lab apply   -var-file=lab.tfvars
terraform -chdir=terraform/environments/lab destroy -var-file=lab.tfvars
```

## Estimated cost

Once both VMs exist (phase 2):

| Item | Hourly | Monthly |
|---|---|---|
| app VM (t3.medium) | $0.0416 | $30.37 |
| Wazuh VM (t3.large) | $0.0832 | $60.74 |
| EBS gp3, ~100 GB total | $0.0110 | $8.00 |
| 1 × public IPv4 (EIP) | $0.0050 | $3.65 |
| **Total** | **~$0.141** | **~$102** |

A short assessment run is what matters: **a 20-hour lab run costs roughly
$2.80.** Phase 1 as applied today (VPC, subnets, IGW, route tables, security
groups) costs **$0.00** — none of those resources are billable.

Tear down with `terraform destroy` after evidence is captured.

## Roadmap

- [x] **Phase 1 — network.** VPC, public/private subnets, IGW, route tables, security groups. Applied and verified.
- [ ] **Phase 2 — compute.** Both VMs, SSM instance profiles, Wazuh EBS volume, cloud-init, private subnet NAT route.
- [ ] **Phase 3 — workloads.** Juice Shop + ingress-nginx/ModSecurity Helm chart, Wazuh agent enrollment, custom detection rule.
- [ ] **Phase 4 — verifier.** Readiness check, unique-marker request, Wazuh Indexer API lookup, WAF allow/block proof, evidence capture.
- [ ] **Phase 5 — CI/CD.** `fmt`/`validate`/tflint, Trivy, Gitleaks, gated deploy on OIDC credentials.

## Verification performed

Phase 1 was checked against the AWS API rather than the apply output:

- Private route table has **no** `0.0.0.0/0` route — fail-closed as intended
- `MapPublicIpOnLaunch` is `false` on **both** subnets
- Default security group has **0** rules
- All 5 Wazuh ingress rules are security-group-referenced, **0** are CIDR-based
- The only `0.0.0.0/0` ingress in the VPC is **udp/51820** (WireGuard)

## Notes

- **Actual effort / AI use / incomplete items:** to be completed at submission.
- **TLS handling:** documented in the security decisions table; self-signed
  certificates on both the WAF ingress and the Wazuh dashboard, since the lab
  is private and has no public domain.
