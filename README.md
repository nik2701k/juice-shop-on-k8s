# Juice Shop on K8s — Wazuh / WAF / VPN lab

Terraform-driven security lab on AWS: OWASP Juice Shop on K3s behind a
ModSecurity WAF, reachable only over WireGuard, with a private Wazuh stack
collecting and indexing the ingress logs.

**Status: network, compute, VPN, K3s, and the WAF applied and verified.**
Juice Shop runs on K3s behind OWASP CRS on ModSecurity, reachable only over
WireGuard, with the private subnet egressing through the app VM rather than a
NAT Gateway.

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

### Tagging

Tags are applied through the provider's `default_tags` rather than per
resource, so no resource can be forgotten and no module has to know the
tagging scheme. `lab.tfvars` supplies the ownership/cost half, merged last so
it can override a baseline value if it ever needs to.

| Tag | Source | Purpose |
|---|---|---|
| `Project` | provider baseline | Groups the lab in Cost Explorer |
| `Env` | provider baseline | Separates this from any future environment |
| `ManagedBy` | provider baseline | Marks resources as Terraform-owned, so nobody edits them by hand |
| `Owner` | `lab.tfvars` | Who to ask before deleting |
| `CostCenter` | `lab.tfvars` | Cost allocation |
| `Repo` | `lab.tfvars` | Traces a resource back to the code that made it |

Three of the 21 resources carry no tags: `aws_route` and the two
`aws_route_table_association`s. **AWS does not support tags on those resource
types at all** — it is not an omission. Everything taggable is tagged, which
the Resource Groups Tagging API confirms at 18 of 18.

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
| **IMDSv2 required** (`http_tokens = "required"`) on both VMs | This lab deliberately runs a vulnerable application. Unauthenticated metadata access is exactly how a server-side request forgery in Juice Shop turns into stolen IAM role credentials. |
| **One IAM role per VM**, not one shared role | They carry the same policy today, but the app VM will need to read Wazuh credentials from SSM Parameter Store and the Wazuh VM must never be able to. |
| **WireGuard keys are generated on the instance**, never by Terraform | A `tls_private_key` resource would write the private key into Terraform state in plaintext. Generating on the box means state holds `PrivateKey = $SERVER_PRIV` — the shell variable, not a value. |
| WireGuard keys are **mirrored to Parameter Store and restored on boot** | Without this, every edit to `user_data` replaces the instance, rotates the keys, and silently kills every peer config already handed out. Verified by forcing a replacement: the server public key was byte-identical afterwards. |
| Client configs published to **SSM Parameter Store as `SecureString`** | KMS-encrypted at rest, fetched on demand, never written to the repo or to state. The app VM's IAM policy can write only `/<project>/wireguard/*`. |
| VPC CIDR is `10.66.0.0/16`, not `10.0.0.0/16` | Found by testing, not by theory: a peer's existing corporate VPN already owned `10/16`, so `wg-quick` could not install the lab's route and probes silently went to the wrong network. `10.0.0.0/16` is among the most-claimed private ranges. |
| VPN is a **split tunnel** (`AllowedIPs = VPC + pool`) | Only lab traffic crosses the tunnel. A peer's ordinary internet traffic is neither routed nor observable here. |
| No key pair exists unless `ssh_public_key` is set | Default is SSM Session Manager only — no key material to distribute, lose, or commit. |
| Root and data volumes **encrypted** | Cheap, and there is no reason not to. |
| State bucket versioning enabled | This is the control that makes a truncated or corrupted state file recoverable. |

### Kubernetes and delivery

| Decision | Why |
|---|---|
| **OWASP CRS container**, not ingress-nginx's ModSecurity | Upstream ingress-nginx has deprecated its ModSecurity integration. The CRS nginx image is one of the options the brief names, is maintained for this purpose, and carries no deprecation risk. |
| CRS rule **920350 excluded** | It flags a numeric IP in the Host header, which this lab always has. It fired on every request and consumed 3 of the 5 points needed to block, leaving an ordinary request two points from being blocked and making the demonstrated block partly dependent on noise. |
| `externalTrafficPolicy: Local` on the WAF Service | K3s's servicelb source-NATs by default, so the WAF logged the CNI gateway as the client for every request. Wazuh would have had no source address to attribute anything to. |
| Audit log part **E dropped** | Part E is the response body. Including it made each record 11 KB, almost entirely a copy of the page just served — 83% of the volume headed for a 50 GB indexer, with no investigative value. |
| A **NetworkPolicy** admits only the WAF pod to Juice Shop | Defence in depth behind the ClusterIP decision: a pod that already has a foothold still cannot reach the application directly. |
| **K3s with Traefik disabled** | ingress-nginx is what carries ModSecurity. Leaving Traefik installed would mean a second ingress controller, and therefore a path around the WAF. |
| K3s version **pinned** in `lab.tfvars` | A rebuild months from now yields the same cluster rather than whatever is current. |
| Manifests live in `k8s/`, **not baked into `user_data`** | Cloud-init is part of the instance's replacement trigger. Manifests placed in K3s's auto-deploy directory that way would make editing a manifest replace the VM — the exact failure this repo already fixed for WireGuard keys. |
| kubeconfig published to SSM, **server URL rewritten** to the private address | The stock file points at `127.0.0.1`, which is useless anywhere but the node. Rewritten, it works directly over the VPN with nothing copied off the box by hand. |
| CD applies manifests over **SSM Send-Command**, not a VPN tunnel in CI | The cluster needs no inbound access at all. CI authenticates with an OIDC role and AWS brokers the command, so no long-lived key to the private network ever sits in GitHub. The alternative — a WireGuard peer key in CI secrets — is a standing credential to the whole VPC. |

### Wazuh

| Decision | Why |
|---|---|
| Docker's `data-root` on the EBS volume | Images and named volumes then sit on the persistent disk, so indices survive an instance replacement rather than being rebuilt empty. |
| Containers are **force-recreated** if `compose up` fails | Container metadata written by a host that no longer exists fails with `RWLayer of container ... is unexpectedly nil`. Containers are disposable, the volumes behind them are not, so the recovery is to recreate them. Found by rebuilding the instance and watching the stack refuse to start. |
| `ExecStop` runs `compose down` | The graceful path: containers are removed on shutdown, so the stale-metadata case only arises on ungraceful termination. Two layers, and the fallback is the one that handles a terminated instance. |
| Indexer, API and dashboard passwords **generated on the instance** | They are minted on first boot, stored in Parameter Store as `SecureString`, and restored on later boots. None of them is in Terraform state or the repo, and the shipped defaults are replaced — verified by confirming `admin/SecretPassword` returns 401. |
| Wazuh's SSM policy is scoped to `/<project>/wazuh/*` | It has no business reading the app VM's WireGuard keys. |
| `wazuh-docker` tag pinned | A rebuild reproduces the same stack rather than whatever is current. |

### Reliability decisions

| Decision | Why |
|---|---|
| Wazuh compose supervised by a **systemd unit**, not a bare `docker compose up -d` | Survives reboot, not just container crash. K3s workloads already get this from the kubelet. |
| `vm.max_map_count` persisted to `/etc/sysctl.d/` | Set live by cloud-init it works on first apply, then the indexer refuses to start after the first reboot. Classic silent failure. |
| Wazuh data on a **separate EBS volume** with `prevent_destroy`, `nofail` in fstab | Satisfies "reruns must preserve data". Miss the fstab entry and Wazuh returns with an empty data dir, which looks exactly like a crash. |
| The data volume is formatted **only if blank** | This single `blkid` check is what makes a rerun preserve the indices rather than silently reformatting them. |
| Mounted by **UUID**, not device name | NVMe device ordering is not stable across reboots. |
| NAT rules re-applied each boot by a **systemd unit**, not written once by cloud-init | A reboot cannot quietly blackhole the private subnet. Each rule is checked before being added, so the script is safe to re-run. |
| `source_dest_check = false` on the app VM | Mandatory for a NAT instance. EC2 drops forwarded packets otherwise, because their source address is not the instance's own. |

---

## Repository layout

```
k8s/                            # cluster manifests, applied separately from Terraform
├── namespace.yaml
├── juice-shop/                 # Deployment, ClusterIP Service, NetworkPolicy
└── waf/                        # OWASP CRS + ModSecurity, LoadBalancer Service

terraform/
├── environments/lab/           # root module: provider, backend, wiring, tfvars
│   ├── lab.tfvars              # committed — the shape of the lab, not secrets
│   └── local.auto.tfvars.example  # copy to local.auto.tfvars for operator IPs
└── modules/
    ├── network/                # VPC, subnets, IGW, route tables, default-SG lockdown
    ├── security-groups/        # app SG + wazuh SG
    └── compute/                # both VMs, IAM roles, EIP, NAT route, Wazuh data volume
        └── templates/          # cloud-init user-data for each VM
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

## Deploy, verify, teardown

### One-time: the state bucket

A state backend cannot store the bucket it lives in, so this is the single
step performed outside Terraform. Run it once per account.

```bash
B=juiceshop-lab-tfstate-<account-id>

aws s3api create-bucket --bucket "$B" --region us-east-1

# Versioning is the control that matters: it makes a truncated or corrupted
# state file recoverable.
aws s3api put-bucket-versioning --bucket "$B" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption --bucket "$B" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'

aws s3api put-public-access-block --bucket "$B" \
  --public-access-block-configuration \
  'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
```

Also attach a bucket policy denying `aws:SecureTransport = false`, so plaintext
requests are rejected outright rather than merely encrypted at rest.

Then write `terraform/environments/lab/backend.hcl`, which is gitignored
because it names the account-scoped state bucket:

```hcl
bucket  = "juiceshop-lab-tfstate-<account-id>"
key     = "lab/terraform.tfstate"
region  = "us-east-1"
profile = "<your-cli-profile>"
```

State locking is native to the S3 backend (`use_lockfile` in `versions.tf`),
so there is no DynamoDB table to create.

Optionally, to reach the lab without joining the VPN, copy
`local.auto.tfvars.example` to `local.auto.tfvars` and set `evaluator_cidrs`
to your address. That file is gitignored, so no operator IP reaches the repo.

### Joining the VPN

The app VM generates every WireGuard key itself and publishes each peer config
to Parameter Store, so no key material passes through Terraform or the repo.

```bash
aws ssm get-parameter --with-decryption \
  --name /juiceshop-lab/wireguard/client-1 \
  --query Parameter.Value --output text > wg-lab.conf

sudo wg-quick up ./wg-lab.conf   # or import wg-lab.conf into the WireGuard app
```

`wg_peer_count` in `lab.tfvars` controls how many peers exist; the default of
two covers one operator and one evaluator. Peer configs match `wg-*.conf`, which
`.gitignore` already excludes.

### Deploy

```bash
cd terraform/environments/lab

terraform init -backend-config=backend.hcl
terraform apply -var-file=lab.tfvars
```

`-var-file` is required: the infrastructure-shape variables have no defaults,
so `lab.tfvars` is their only source and cannot silently disagree with one.

### Verify

```bash
terraform fmt -recursive -check       # from the repo root, so modules/ is in scope
terraform -chdir=terraform/environments/lab validate
terraform -chdir=terraform/environments/lab plan -var-file=lab.tfvars
```

A clean deploy re-plans to zero changes.

### Teardown

```bash
terraform destroy -var-file=lab.tfvars
```

Destroy leaves the state bucket in place; it is created out of band and
holds the history of every apply. Delete it by hand if the account is being
retired.

## Estimated cost

Once both VMs exist:

| Item | Hourly | Monthly |
|---|---|---|
| app VM (t3.medium) | $0.0416 | $30.37 |
| Wazuh VM (t3.large) | $0.0832 | $60.74 |
| EBS gp3, ~100 GB total | $0.0110 | $8.00 |
| 1 × public IPv4 (EIP) | $0.0050 | $3.65 |
| **Total** | **~$0.141** | **~$102** |

A short assessment run is what matters: **a 20-hour lab run costs roughly
$2.80.** The network layer as applied today (VPC, subnets, IGW, route tables,
security groups) costs **$0.00** — none of those resources are billable.

Tear down with `terraform destroy` after evidence is captured.

## Evidence

- [`evidence/waf-blocking.md`](evidence/waf-blocking.md) — one allowed and one
  deterministic blocked request with the CRS rule that caused it, plus three
  independent proofs that direct-origin bypass is closed.
- [`evidence/vpn-access.md`](evidence/vpn-access.md) — private access over
  WireGuard, including proof that the far-side host is the lab's own and that
  security groups are enforced across the tunnel.

## Notes

- **Actual effort / AI use / incomplete items:** to be completed at submission.
- **TLS handling:** documented in the security decisions table; self-signed
  certificates on both the WAF ingress and the Wazuh dashboard, since the lab
  is private and has no public domain.
