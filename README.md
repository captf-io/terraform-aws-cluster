# terraform-aws-cluster

The CAPTF AWS cluster module: the Terraform/OpenTofu root module behind `TerraformCluster`. The images are published from [aws-modules](https://github.com/captf-io/aws-modules) as `ghcr.io/captf-io/aws-cluster`; this repository holds the module code only.

The `cluster` role for AWS: what every machine and pool of one cluster
shares. It implements the `v1alpha1`
[cluster role](https://captf.io/docs/module-author/contract/v1alpha1/cluster.html)
and ships as `ghcr.io/captf-io/aws-cluster`. The network is yours: the
module creates the API endpoint, the security groups, the node identities
and a bootstrap bucket inside a VPC and subnets that already exist.

## What it creates

| Resource | Count | Purpose |
| --- | --- | --- |
| `aws_lb.api_load_balancer` | 0 or 1 | Network Load Balancer for the Kubernetes API, internal by default; none with a user endpoint |
| `aws_lb_target_group.api_target_groups` | 1 per API port | TCP target group on the backend port (the API port with kubeadm, always 6443 for RKE2's kube-apiserver; 9345 for the RKE2 supervisor); control-plane machines register in it |
| `aws_lb_listener.api_listeners` | 1 per API port | TCP listener on the endpoint port (`api_server_port`, 9345), forwarding to its target group |
| `terraform_data.api_endpoint_guard` | 0 or 1 | Records the scheme, port and subnets the load balancer was created with; its postcondition fails any plan that would change them |
| `aws_security_group.api_load_balancer_security_group` | 0 or 1 | The load balancer's group |
| `aws_security_group.control_plane_security_group` | 1 | Control-plane nodes: the API backend ports from the load balancer and the pods |
| `aws_security_group.node_security_group` | 1 | Every node; the only group tagged for the cloud controller manager |
| `aws_vpc_security_group_ingress_rule.api_load_balancer_ingress_rules` | per port and source | Nodes and `api_allowed_cidrs` to the API ports |
| `aws_vpc_security_group_egress_rule.api_load_balancer_egress_rules` | per port | The load balancer to the control-plane nodes, traffic and health checks |
| `aws_vpc_security_group_ingress_rule.control_plane_ingress_rules` | per rule | API backend ports from the load balancer and the pod CIDRs (from `api_allowed_cidrs` with a user endpoint) |
| `aws_vpc_security_group_ingress_rule.node_ingress_rules` | per rule | All traffic between the cluster's nodes (any CNI, etcd, kubelet), and SSH from `ssh_allowed_cidrs` |
| `aws_vpc_security_group_egress_rule.node_egress_rules` | 1 | All outbound traffic from the nodes |
| `aws_iam_role.node_roles` | 0 to 2 | Control-plane and worker roles under `/captf/`, each unless `control_plane_instance_profile` or `worker_instance_profile` brings one |
| `aws_iam_role_policy.node_role_policies` | 0 or 2 | The cloud-provider-aws policies: the Node Policy for workers, the Control Plane Policy and the Node Policy for control-plane nodes |
| `aws_iam_role_policy_attachment.node_role_policy_attachments` | 1 per policy | `node_role_policy_arns` |
| `aws_iam_instance_profile.node_instance_profiles` | 0 to 2 | The instance profiles machines and pools launch with |
| `aws_s3_bucket.bootstrap_bucket` | 1 | Holds the bootstrap payloads machines and pools stage |
| `aws_s3_bucket_public_access_block.bootstrap_bucket_public_access` | 1 | Blocks all public access |
| `aws_s3_bucket_server_side_encryption_configuration.bootstrap_bucket_encryption` | 1 | SSE-S3 |
| `aws_s3_bucket_policy.bootstrap_bucket_policy` | 1 | TLS only; each node role reads only its own key prefixes |

It reads `data.aws_subnets.node_subnets`,
`data.aws_subnets.api_load_balancer_subnets` (which return nothing rather
than fail, so a destroy still runs after a subnet is gone),
`data.aws_vpcs.cluster_vpcs` (likewise a listing), `data.aws_vpc.cluster_vpc`
(only when the VPC exists and an internal endpoint defaults to its CIDR),
`data.aws_region.current_region` and
`data.aws_partition.current_partition`. Brought instance profiles are not
read: their role ARNs are inputs.

## Prerequisites

- **Network.** A VPC and one subnet per availability zone for the nodes,
  with routes to what the nodes pull from (the internet through NAT, or VPC
  endpoints for S3, ECR, EC2 and STS plus a registry mirror). Each zone is a
  failure domain. An internet-facing API load balancer needs public subnets
  (`api_load_balancer_subnets`), one in every zone of the node subnets: a
  Network Load Balancer sends no traffic to targets in a zone it is not in. For Service load balancers,
  cloud-provider-aws finds subnets by the `kubernetes.io/role/elb` and
  `kubernetes.io/role/internal-elb` tags, which you set.
- **The management cluster must reach the endpoint.** An internal load
  balancer is reachable from the VPC and the networks routed to it: add the
  management cluster's CIDR to `api_allowed_cidrs` if it is not in the VPC.
- **Quotas.** One Network Load Balancer, three security groups (each rule
  counts against the rules-per-group quota), two IAM roles and instance
  profiles, one S3 bucket.
- **Identity permissions.** The identity creates and deletes the resources
  above: [`examples/identity-policy.json`](examples/identity-policy.json)
  covers all three roles. It needs `iam:CreateRole` and friends on
  `role/captf/*` and `instance-profile/captf/*`, unless the node identities
  are brought.
- **Images.** None: the cluster role launches no instances.

## Inputs

Contract inputs ([cluster role](https://captf.io/docs/module-author/contract/v1alpha1/cluster.html#inputs)):

| Input | Used for |
| --- | --- |
| `captf_contract` | Validated to be `v1alpha1` |
| `captf_cluster` | Every name (namespace and name, with a hash) |
| `captf_object` | Declared, unused |
| `captf_cluster_outputs` | Declared with `default = null`, never passed to the cluster role |
| `captf_tags` | Tags on every taggable resource |
| `control_plane_endpoint` | Non-null: no load balancer; passed through to the output |
| `kubernetes_version` | Declared, unused |
| `control_plane_initialized` | Declared, unused: nothing here needs a live API server |
| `cluster_network` | `api_server_port` (default 6443) sets the endpoint port, and the backend port with kubeadm; `pods` (IPv4) opens the API backend port to the pod CIDRs |

User variables, set through `spec.variables` or `spec.variablesFrom` on the
TerraformCluster:

| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `additional_tags` | `map(string)` | `{}` | Extra tags for every taggable resource; at most 40, no `aws:`, `captf.io/` or `kubernetes.io/cluster/` keys. |
| `api_allowed_cidrs` | `list(string)` | `[]` | IPv4 networks allowed to reach the API besides the nodes. Empty: the VPC's primary CIDR for an internal load balancer. Required for an internet-facing one, and must then include the nodes' public egress addresses (the NAT gateways' Elastic IPs as `/32`s). |
| `api_load_balancer_public` | `bool` | `false` | Make the API load balancer internet-facing. |
| `api_load_balancer_subnets` | `map(string)` | `{}` | Availability zone to subnet ID for the API load balancer; empty means the node subnets. It must cover every zone of `subnets`, and is required (public subnets) for an internet-facing one. Subnets present at creation can never be removed. |
| `control_plane_instance_profile` | `object({name, role_arn})` | `null` | An existing instance profile for control-plane nodes, with its role's ARN, instead of creating one. |
| `distribution` | `string` | `"kubeadm"` | `kubeadm` or `rke2`; `rke2` adds the supervisor listener on 9345 and puts the kube-apiserver backend on 6443. |
| `node_role_permissions_boundary` | `string` | `null` | Permissions boundary ARN for the node roles the module creates; it must allow `s3:GetObject` on `captf-bootstrap-*` and the cloud-provider-aws and ECR actions. |
| `node_role_policy_arns` | `object({control_plane, worker})` | `{}` | Managed policies to attach to the node roles the module creates. |
| `region` | `string` | `null` | AWS region; null uses `AWS_REGION` from the identity Secret. |
| `ssh_allowed_cidrs` | `list(string)` | `[]` | IPv4 networks allowed to reach the nodes on SSH (22); none by default. |
| `subnets` | `map(string)` | `null` (required) | Availability zone to node subnet ID, one subnet per zone. |
| `vpc_id` | `string` | `null` (required) | The VPC of the subnets. |
| `worker_instance_profile` | `object({name, role_arn})` | `null` | An existing instance profile for workers, with its role's ARN, instead of creating one; its role must differ from the control-plane one. |

## Outputs

| Output | Value |
| --- | --- |
| `control_plane_endpoint` | `{ host = <load balancer DNS name>, port = <API port> }`, or the input passed through. Stable for the load balancer's life. |
| `failure_domains` | One per subnet zone, sorted: `{ name = <zone>, control_plane = true, attributes = { subnet_id } }`. |
| `exports` | See Exports. |
| `health` | See Health. |

Non-contract output (`outputs_extra.tf`): `api_load_balancer_id`, the
Network Load Balancer's ARN.

## Exports

Schema `captf.io/aws-cluster/v1`. Machines and pools read it as
`captf_cluster_outputs`; for an externally managed TerraformCluster, give
them the same object as `external_cluster_exports`.

```hcl
{
  schema                = "captf.io/aws-cluster/v1"
  region                = "us-east-1"
  vpc_id                = "vpc-0123456789abcdef0"
  kubernetes_cluster_id = "captf-team-a-demo-1960e37c" # kubernetes.io/cluster/<id>
  failure_domains       = { "us-east-1a" = { subnet_id = "subnet-..." } }
  security_group_ids    = { control_plane = ["sg-<control plane>", "sg-<node>"], worker = ["sg-<node>"] }
  instance_profiles     = { control_plane = "<name>", worker = "<name>" }
  api = { # null with a user endpoint
    host          = "<load balancer DNS name>"
    port          = 6443 # the endpoint port
    target_groups = { kube_apiserver = { arn = "arn:...", port = 6443 } } # port: the backend port to register
  }
  bootstrap_bucket      = "captf-bootstrap-..."
}
```

Nothing in it is secret. Adding a key keeps the schema; renaming or
removing one makes it `captf.io/aws-cluster/v2`.

## Identity Secret

The provider block sets only the region; every credential comes from the
identity's Secret through the AWS SDK's default chain. Either static keys:

```yaml
stringData:
  AWS_ACCESS_KEY_ID: <access key ID>
  AWS_SECRET_ACCESS_KEY: <secret access key>
  AWS_REGION: us-east-1
```

or a role to assume, through shared config files the Job sees under
`/var/run/captf/credentials/`:

```yaml
stringData:
  AWS_CONFIG_FILE: /var/run/captf/credentials/config
  AWS_SHARED_CREDENTIALS_FILE: /var/run/captf/credentials/credentials
  AWS_PROFILE: captf
  AWS_REGION: us-east-1
  config: |
    [profile captf]
    role_arn = arn:aws:iam::123456789012:role/captf-provisioner
    source_profile = base
  credentials: |
    [base]
    aws_access_key_id = <access key ID>
    aws_secret_access_key = <secret access key>
```

`HOME` is `/captf/work` in the Job, so `~/.aws` never exists. IRSA and Pod
Identity do not apply: the Job mounts no projected service account token.
See [`examples/identity.yaml`](examples/identity.yaml).

## Tags

Every taggable resource carries `captf_tags` with their keys unchanged
(`captf.io/cluster`, `captf.io/namespace`, `captf.io/kind`, `captf.io/name`,
`captf.io/managed-by`, `captf.io/template`), merged over `additional_tags`
so those cannot override them. Security groups also carry `Name`. The node
security group alone carries `kubernetes.io/cluster/<id> = owned`.

Not taggable: `aws_iam_role_policy`, `aws_iam_role_policy_attachment`, the
bucket's public access block, encryption configuration and policy, and
`terraform_data`.

## Health

| Condition | `state` | `healthy` | `reasons` |
| --- | --- | --- | --- |
| The API load balancer (the primary resource, when the module owns the endpoint) was deleted out of band | `terminated` | `false` | `LoadBalancerNotFound` |
| The bootstrap bucket was deleted out of band | `degraded` | `false` | `BootstrapBucketNotFound` |
| Both exist | `running` | `true` | `[]` |

Target health is never consulted: targets are unhealthy during every
normal control-plane bring-up, and cluster health feeds `Ready`.

## Limitations

- **The endpoint is fixed at creation.** Changing `api_load_balancer_public`
  or `cluster_network.api_server_port`, or removing a load balancer
  subnet the load balancer was created with, would replace it or move the
  endpoint; `api_endpoint_guard` makes such a plan fail with an
  explanation instead. Adding subnets works in place, but removing a subnet
  added later is not caught by the guard and replaces the load balancer:
  only CAPTF's destructive-plan approval stops it.
- **An internet-facing endpoint** needs public subnets for the load
  balancer and the nodes' public egress addresses in `api_allowed_cidrs`:
  its DNS name resolves to public addresses, so node traffic arrives from
  the NAT gateways, never from the node group.
- **Nodes accept all traffic from each other** (the node group to itself,
  control-plane nodes included): any CNI works, and a worker can reach
  control-plane ports such as etcd.
- **Workers are denied the control-plane payloads** by the bucket policy,
  whatever their own policies allow; any other principal of the account
  with broad S3 read can still read them.
- **Brought instance profiles** are not read, so their deletion never
  blocks a destroy; the module trusts the role ARNs given.
- **The node identities are created per cluster** with fixed names
  (`captf-<namespace>-<name>-<hash>-control-plane` and `-worker`): two
  management clusters cannot create the same `namespace/name` cluster in
  one account.
- **No EBS CSI permissions by default.** Attach
  `arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy` through
  `node_role_policy_arns` to the role of the nodes the EBS CSI controller
  runs on, and raise their `instance_metadata_hop_limit` to 2 if it runs
  without host networking.
- **Nodes egress everywhere** (`0.0.0.0/0`, all protocols): restrict egress
  in the network you bring (route tables, NACLs, a firewall).
- **Service load balancers** created by cloud-provider-aws are not
  deleted with the cluster: delete the Services (or the load balancers)
  first, or the node security group and subnets can stay in use.

## Exceptions

None: `tfcapi-lint module --strict` passes without allowed warnings.

## Examples

[`examples/cluster-kubeadm.yaml`](examples/cluster-kubeadm.yaml) creates
a TerraformCluster with:

```yaml
spec:
  source:
    image: ghcr.io/captf-io/aws-cluster:v0.1.0-opentofu
  variables:
    region: us-east-1
    vpc_id: vpc-0123456789abcdef0
    subnets:
      us-east-1a: subnet-0aaa0000000000001
      us-east-1b: subnet-0bbb0000000000002
      us-east-1c: subnet-0ccc0000000000003
```

## Development

The host needs `make`, `podman` (or `docker` with `ENGINE=docker`), `jq` and
Go; every other tool runs in a digest-pinned container. `make verify` is the
gate. `tfcapi-lint` is built from `../cluster-api-provider-terraform`
(`PROVIDER_DIR`); without that checkout the target skips.

| Target | What it does |
| --- | --- |
| `make fmt` | Format the module with `terraform fmt` and `tofu fmt`, in place. |
| `make fmt-check` | Fail on any file either formatter would change. |
| `make validate` | `init` and `validate` on both runtimes and on their floors (Terraform 1.5.7, OpenTofu 1.6.3). |
| `make unit-test` | `terraform test` and `tofu test` with mocked providers. |
| `make tflint` | `tflint` with the terraform ruleset (preset all) and the cloud ruleset. |
| `make tfcapi-lint` | `tfcapi-lint module --strict`. |
| `make scan` | `trivy config` over the repository; ignores live in `.trivyignore.yaml`. |
| `make check-conventions` | `hack/check-layout.sh` and `hack/check-tags.sh` (CONVENTIONS.md). |
| `make shellcheck` | `shellcheck` over `hack/` and every shell template, rendered with placeholders. |
| `make check-headers` | Fail on any source file without the Apache-2.0 license header. |
| `make fix-headers` | Add the license header to every source file missing it. |
| `make verify` | Everything above, in parallel groups. |
| `make clean` | Remove `build/`. |

`RUNTIMES=opentofu` limits a run to one runtime.
