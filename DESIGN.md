# Design: terraform-aws-cluster

Why this module looks the way it does. Each decision names the evidence it
rests on; anything not yet checked against a real AWS account is listed
under "Unverified" and must be confirmed on the first reviewed apply.

Pins: `hashicorp/aws` 6.67.0. Runtimes: Terraform >= 1.5, OpenTofu >= 1.6.
Conventions: [CONVENTIONS.md](CONVENTIONS.md). Contract:
<https://captf.io/docs/module-author/contract/v1alpha1/>.

Provider facts below were checked against `providers schema -json` of the
pinned provider and its source at the `v6.67.0` tag; file names refer to
`internal/service/<service>/` in `hashicorp/terraform-provider-aws`.

The AWS modules share one design. Decision numbers are the same in every
repository ([cluster](https://github.com/captf-io/terraform-aws-cluster/blob/main/DESIGN.md), [machine](https://github.com/captf-io/terraform-aws-machine/blob/main/DESIGN.md), [machinepool](https://github.com/captf-io/terraform-aws-machinepool/blob/main/DESIGN.md)), so a reference such as "decision 1" means the same
decision everywhere; a number missing here belongs to another role.

## Scope

- This repository is the `cluster` role. The `machine` and `machinepool` roles are in
  [terraform-aws-machine](https://github.com/captf-io/terraform-aws-machine) and
  [terraform-aws-machinepool](https://github.com/captf-io/terraform-aws-machinepool).
- Bring-your-own network: the VPC, subnets, NAT, routes and endpoints exist
  before the cluster. The cluster role creates security groups, the API
  load balancer, the node identities and a bootstrap bucket.
- The API load balancer is internal by default; internet-facing is opt-in
  and needs an explicit allowed-CIDR list.
- Node identities (IAM roles and instance profiles) are created by default,
  with a variable to bring existing instance profiles instead.


## Decisions

### 1. Bootstrap payloads are staged in S3

The contract suggests `aws_launch_template.user_data = var.bootstrap_data`
for pools. Pool bootstrap data rotates about every 7.5 minutes (kubeadm
token refresh), and every user-data change creates a launch template
version. AWS allows 10,000 versions per launch template (EC2 User Guide,
"Restrictions for launch templates"): about 52 days of rotations, after
which every pool apply fails. Terraform has no resource that prunes
versions. Secrets Manager (100 unlabelled versions, none removed within 24
hours) and SSM Parameter Store (4 KB / 8 KB values) do not fit either.

So the cluster creates one S3 bucket per cluster. The machine and pool
roles write the payload to an object in it and give the instance a small
user-data stub that fetches it; the stubs and delivery modes are in the
[machine](https://github.com/captf-io/terraform-aws-machine/blob/main/DESIGN.md) and [machinepool](https://github.com/captf-io/terraform-aws-machinepool/blob/main/DESIGN.md) DESIGN.md files.

Bucket: `bucket_prefix = "captf-bootstrap-"`, public access block (all
four), SSE-S3 stated explicitly, a policy denying non-TLS access,
`force_destroy = true` (cluster destroy runs only after every machine and
pool is gone). The policy waits for the public access block (`depends_on`):
S3 rejects concurrent configuration changes to one bucket
(`OperationAborted`, hashicorp/terraform-provider-aws#7628).

Read access is granted by the **bucket policy**, by key prefix and node
role ARN: control-plane nodes read `control-plane/*`, workers read
`worker/*` and `pool/*`, and an explicit Deny keeps the worker role out of
`control-plane/*` (the payloads embed the cluster CA keys) whatever its
own policies allow; within one account either policy can grant, so the
allows alone would not. Other principals of the account with broad S3
read can still read the payloads. Control-plane and worker roles must
differ. The provider retries `PutBucketPolicy`
on `MalformedPolicy` for two minutes (`s3/bucket_policy.go`), which covers
a role ARN IAM has not propagated yet.

### 2. API load balancer: NLB with client IP preservation off

- Network Load Balancer, internal by default.
- `preserve_client_ip = false` on the target groups: "NAT loopback, also
  known as hairpinning, is not supported when client IP preservation is
  enabled" (NLB troubleshooting). The contract requires control-plane
  nodes to reach the endpoint themselves.
- The NLB gets a security group at creation: an NLB created without
  security groups cannot get them later (the provider forces replacement
  when groups are added to an NLB that has none, `elbv2/load_balancer.go`
  `customizeDiffLoadBalancerNLB`).
- One target group and listener per port: kube-apiserver and, with
  `distribution = "rke2"`, the RKE2 supervisor on 9345. The listener is on
  the endpoint port (`cluster_network.api_server_port`, default 6443), the
  target group on the backend port: the same with kubeadm, always 6443
  with RKE2, whose kube-apiserver ignores `apiServerPort`
  (control-planes/rke2.md). An `api_server_port` of 9345 with RKE2 fails
  a precondition (two listeners on one port). Exports give the endpoint
  `host` and `port`, and per target group the backend port to register.
- TCP health checks every 10 s, thresholds 2/2, deregistration delay 30 s,
  cross-zone load balancing on.
- The endpoint is the NLB DNS name, stable for the NLB's life. No
  `prevent_destroy`: it would also block cluster deletion. Replacement is
  stopped by CAPTF's destructive-plan guard, and
  `terraform_data.api_endpoint_guard` records at creation what would
  replace the NLB or move the endpoint: the scheme (`internal` is
  ForceNew), the port (a listener change in place), and the subnets
  (removing a subnet from an NLB is ForceNew, adding one is in place,
  `customizeDiffLoadBalancerNLB`). One postcondition on the guard fails a
  plan that would change any of them, naming each with its recorded and
  requested value (CONVENTIONS.md section 12). The guard keeps the subnets of the creation only (it cannot
  ratchet without referring to itself), so removing a subnet added later
  is left to the destructive-plan guard; the README says so.
- An internet-facing NLB resolves to public addresses, so the nodes'
  traffic to it, the control-plane hairpin included, arrives from their
  public egress addresses (NAT gateway Elastic IPs), which a security group
  reference never matches. `api_allowed_cidrs`, required with
  `api_load_balancer_public`, must list them, as in the other four
  repositories; so is `api_load_balancer_subnets` (public subnets: AWS
  accepts an internet-facing NLB in private subnets, unreachable, and its
  subnets can never be removed). CAPA adds the NAT gateway EIPs the same
  way (`securitygroups.go`
  `getIngressRulesToAllowKubeletToAccessTheControlPlaneLB`); they are an
  input here rather than read with `aws_nat_gateway`, whose singular read
  would fail a destroy once a gateway is gone.
- Without the module's NLB (a user endpoint), the API port opens on the
  control-plane group to `api_allowed_cidrs` directly.
- The NLB's subnets (`api_load_balancer_subnets`, zone to subnet) must
  cover every node zone, a precondition: targets in a zone the load
  balancer is not enabled in receive no traffic (ELB User Guide, "Availability
  Zones").

### 3. Security groups

- A node group attached to every node, and the only group tagged
  `kubernetes.io/cluster/<id> = owned`: cloud-provider-aws fails with
  "Multiple tagged security groups found for instance" otherwise
  (`findSecurityGroupForInstance`). It has `revoke_rules_on_delete`, since
  the cloud controller manager adds rules to it.
- A control-plane group (not cluster-tagged) and a load balancer group.
- Rules are separate `aws_vpc_security_group_ingress_rule` /
  `_egress_rule` resources over keyed maps, never inline, so rules the CCM
  adds for Services never drift and adding a rule never replaces others.
- Node ingress: all traffic from the node group itself, which every node
  carries, control-plane nodes included (operator decision, CONVENTIONS.md
  section 8): any CNI, webhook, etcd peer and kubelet works without a port
  list; a worker can therefore reach control-plane ports such as etcd.
  SSH only from `ssh_allowed_cidrs` (none by default).
- Control-plane ingress: the API backend ports from the LB group, and the
  kube-apiserver from the (IPv4) pod CIDRs, which a native-routing CNI
  uses as sources; with a user endpoint, from `api_allowed_cidrs`.
- Egress: Terraform removes the default allow-all egress rule of every
  group it creates, so nodes get an explicit all-traffic egress rule, and
  the LB group egress to the control-plane group on the API ports.

### 4. Node identities

Created by default, one role and instance profile each for control plane
and workers, `path = "/captf/"`, trust `ec2.<dns_suffix>` (works in aws-cn
and aws-us-gov through `data.aws_partition`):

- control plane: the "Control Plane Policy" of cloud-provider-aws v1.36.1
  `docs/prerequisites.md`, plus its "Node Policy" (the control-plane
  kubelet pulls from ECR like any other);
- workers: the "Node Policy".

No managed policy is attached by default (`node_role_policy_arns` attaches
them per role), and `node_role_permissions_boundary` sets a boundary for
accounts that require one; it limits the bucket policy's grant to the
role ARN too, so it must allow `s3:GetObject` on the bucket. S3 read access
comes from the bucket policy (decision 1), not from the roles, so a
brought identity (`control_plane_instance_profile`,
`worker_instance_profile`: independent, each a name and a role ARN) needs
no S3 permission of its own; two brought roles must differ, a
precondition, because the bucket denies the worker role the control-plane
payloads. The role ARN is an input rather than read with
`aws_iam_instance_profile`, which fails once the profile is gone and would
block every refresh and destroy (destroy reads data sources).

Policies are built with `jsonencode()` in locals, not
`data.aws_iam_policy_document`: a mocked data source returns a random
string, and the policies must be testable.

### 5. Machine

This role does not own this decision: see the [terraform-aws-machine DESIGN.md](https://github.com/captf-io/terraform-aws-machine/blob/main/DESIGN.md).

### 6. Machine pool

This role does not own this decision: see the [terraform-aws-machinepool DESIGN.md](https://github.com/captf-io/terraform-aws-machinepool/blob/main/DESIGN.md).

### 7. Health

- Cluster health is the presence of the NLB (when the module owns the
  endpoint; gone, the primary resource reads `terminated`,
  `LoadBalancerNotFound`) and the bootstrap bucket (gone: `degraded`),
  never target health: cluster health feeds `Ready`, and targets are
  unhealthy during every normal bring-up. Presence is the length of the
  counted resource, known at plan time too.

### 8. Tags

- `local.tags` on every taggable resource, explicitly. No provider
  `default_tags`: they do not reach ASG-launched instances, and mocks cannot
  assert them.
- Instances also carry `Name` and `kubernetes.io/cluster/<id> = owned`
  (the CCM discovers the cluster ID from its own instance's tags).
- Limits: 50 tags, keys 128, values 256, `aws:` reserved, empty values
  allowed. S3 objects take at most 10 tags, so objects carry only the
  captf tags (`hack/tags.json`).

### 9. Credentials

The provider block sets only `region` (cluster: `var.region`, null means
`AWS_REGION`; machine and pool: the cluster's exported region). Everything
else comes from the SDK chain:

- static keys: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`;
- assume role: `AWS_CONFIG_FILE=/var/run/captf/credentials/config`,
  `AWS_SHARED_CREDENTIALS_FILE=/var/run/captf/credentials/credentials`,
  `AWS_PROFILE`, with `config` and `credentials` file keys in the Secret.

`HOME` is `/captf/work`, so `~/.aws` never exists. IRSA needs a projected
token the CAPTF Job does not mount.

### 10. Network input

The cluster takes `vpc_id` and `subnets`, a map of availability zone to
subnet ID (and `api_load_balancer_subnets`, the same shape). `aws_subnets`
reads each subnet with its zone and the VPC as filters and returns no ID,
rather than failing, when nothing matches: destroy reads data sources too,
and a subnet deleted before the cluster must not block it. Preconditions
(which destroy skips) report a subnet mapped to the wrong zone or VPC.
The VPC is listed the same way (`aws_vpcs`, filtered on `vpc-id`); the
singular `aws_vpc`, for the primary CIDR an internal endpoint defaults to,
is read only when that listing found the VPC, so a VPC deleted before a
retried destroy (the security groups already gone) never blocks it. A
precondition reports a `vpc_id` that names no VPC.

Resources whose disappearance health must report (the bucket, the
instance, the group) use `count = 1`: once a refresh drops a bare
resource from state its references read as unknown, which `try()` cannot
catch, so outputs go null; an empty tuple fails the index and `try()` falls
back (checked with local_file on Terraform 1.16.4 and OpenTofu 1.12.6). A list of subnets with
zones read from AWS was rejected: one subnet per zone and one VPC then need
cross-instance checks that OpenTofu's mocks cannot exercise (overrides
cannot target one `for_each` instance).

## Exports (`captf.io/aws-cluster/v1`)

```hcl
{
  schema                = "captf.io/aws-cluster/v1"
  region                = "<region>"
  vpc_id                = "vpc-..."
  kubernetes_cluster_id = "<id>"
  failure_domains       = { "<az>" = { subnet_id = "subnet-..." } }
  security_group_ids    = { control_plane = ["sg-...", "sg-..."], worker = ["sg-..."] }
  instance_profiles     = { control_plane = "<name>", worker = "<name>" }
  api = { # null for a user endpoint
    host          = "<load balancer DNS name>"
    port          = 6443 # the endpoint port
    target_groups = { kube_apiserver = { arn = "...", port = 6443 } } # the backend port
  }
  bootstrap_bucket      = "<bucket>"
}
```

Machines and pools normalize the exports into one shape with `try()` per
field, and select them from `captf_cluster_outputs` or
`external_cluster_exports` with a tuple index: a conditional refuses two
object values of different shapes.

## Unverified

**1.** Concerns another role: see the DESIGN.md of [terraform-aws-machine](https://github.com/captf-io/terraform-aws-machine/blob/main/DESIGN.md) and [terraform-aws-machinepool](https://github.com/captf-io/terraform-aws-machinepool/blob/main/DESIGN.md).

**2.** Concerns another role: see the DESIGN.md of [terraform-aws-machinepool](https://github.com/captf-io/terraform-aws-machinepool/blob/main/DESIGN.md).

**3.** Concerns another role: see the DESIGN.md of [terraform-aws-machinepool](https://github.com/captf-io/terraform-aws-machinepool/blob/main/DESIGN.md).

**4.** Concerns another role: see the DESIGN.md of [terraform-aws-machine](https://github.com/captf-io/terraform-aws-machine/blob/main/DESIGN.md).

**5.** Service load balancers left by the CCM can block node security group
deletion at cluster destroy.

**6.** NLB idle timeout (350 s) and long `kubectl logs -f` sessions.

**7.** That the NAT gateways' Elastic IPs are the source of node traffic to an
internet-facing NLB in every routing setup users bring.

**8.** `examples/identity-policy.json` is complete for create, update and
destroy of all three roles.

**9.** Concerns another role: see the DESIGN.md of [terraform-aws-machine](https://github.com/captf-io/terraform-aws-machine/blob/main/DESIGN.md) and [terraform-aws-machinepool](https://github.com/captf-io/terraform-aws-machinepool/blob/main/DESIGN.md).

**10.** Concerns another role: see the DESIGN.md of [terraform-aws-machinepool](https://github.com/captf-io/terraform-aws-machinepool/blob/main/DESIGN.md).

## Rejected alternatives

- Bootstrap in launch template user data (version quota, above).
- Provider `default_tags` (does not reach ASG launches; untestable).
- `prevent_destroy` on the NLB (blocks cluster deletion).
- `AmazonEBSCSIDriverPolicy` on the control-plane role and hop limit 2 for
  control-plane nodes by default: the EBS CSI controller does not run on
  control-plane nodes unless scheduled there, and the defaults stay least
  privilege; `node_role_policy_arns` and `instance_metadata_hop_limit` opt
  in.
- Inline `s3:GetObject` policies on the node roles: they would not cover
  brought identities.
- A list of CNI ports between nodes (`cni_ingress_rules`): each CNI, mode
  and webhook needs its own; nodes of one cluster accept all traffic from
  each other instead (CONVENTIONS.md section 8).
- A separate `api_node_egress_cidrs` for an internet-facing endpoint: the
  NAT addresses go in `api_allowed_cidrs`, like every other client.
