# Copyright 2026 The CAPTF Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Unit tests of the cluster role with a mocked AWS provider: nothing reaches
# AWS. `make unit-test ROLES=cluster` runs them on Terraform and OpenTofu.
#
# Runs share state in file order, so the variants plan first, against no
# state, then happy_path applies and a second apply checks it is stable.
# cluster_endpoint_guard.tftest.hcl changes endpoint inputs between applies.
#
# The cluster is team-a/demo: sha256("team-a/demo") starts 1960e37c, so every
# name below ends in that hash.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }
  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }
  mock_data "aws_vpc" {
    defaults = {
      cidr_block = "10.0.0.0/16"
    }
  }
  # vpc_id names one VPC.
  mock_data "aws_vpcs" {
    defaults = {
      ids = ["vpc-0123456789abcdef0"]
    }
  }
  # One match per subnet read: every subnet is where the map says.
  mock_data "aws_subnets" {
    defaults = {
      ids = ["subnet-0aaa0000000000001"]
    }
  }
  # ARNs are validated by the provider's schema even when mocked. The load
  # balancer's DNS name is left random: the endpoint host is then evidence
  # that a second apply kept the load balancer.
  mock_resource "aws_lb" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/captf-team-a-demo-1960e37c/0123456789abcdef"
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/captf-team-a-demo-1960e37c-kapi/0123456789abcdef"
    }
  }
}

variables {
  captf_contract            = "v1alpha1"
  captf_cluster             = { name = "demo", namespace = "team-a" }
  captf_object              = { kind = "TerraformCluster", name = "demo", namespace = "team-a" }
  captf_tags                = { "captf.io/cluster" = "demo", "captf.io/namespace" = "team-a", "captf.io/kind" = "TerraformCluster", "captf.io/name" = "demo", "captf.io/managed-by" = "captf", "captf.io/template" = "" }
  control_plane_endpoint    = null
  kubernetes_version        = "v1.34.1"
  control_plane_initialized = false
  cluster_network           = { pods = ["192.168.0.0/16"], services = ["10.128.0.0/12"], service_domain = "cluster.local", api_server_port = 6443 }
  vpc_id                    = "vpc-0123456789abcdef0"
  subnets                   = { "us-east-1a" = "subnet-0aaa0000000000001", "us-east-1b" = "subnet-0bbb0000000000002" }
  additional_tags           = { team = "platform" }
}

run "exports_shape" {
  command = plan

  assert {
    condition     = toset(keys(output.exports)) == toset(["schema", "region", "vpc_id", "kubernetes_cluster_id", "failure_domains", "security_group_ids", "instance_profiles", "api", "bootstrap_bucket"])
    error_message = "exports must hold exactly the keys of captf.io/aws-cluster/v1."
  }
  assert {
    condition     = output.exports.schema == "captf.io/aws-cluster/v1" && jsonencode(keys(output.exports.failure_domains)) == jsonencode([for d in output.failure_domains : d.name])
    error_message = "exports must name its schema and carry the same failure domains as the failure_domains output."
  }
  assert {
    condition     = keys(output.exports.security_group_ids) == ["control_plane", "worker"] && keys(output.exports.instance_profiles) == ["control_plane", "worker"]
    error_message = "exports must carry security groups and an instance profile for both node kinds."
  }
}

run "api_server_port_override" {
  command = plan

  variables {
    cluster_network = { pods = [], services = [], service_domain = null, api_server_port = 7443 }
  }

  assert {
    condition     = aws_lb_target_group.api_target_groups["kube_apiserver"].port == 7443 && aws_lb_listener.api_listeners["kube_apiserver"].port == 7443
    error_message = "the target group and listener must follow cluster_network.api_server_port."
  }
  assert {
    condition     = output.exports.api.target_groups.kube_apiserver.port == 7443
    error_message = "the exported target group port must follow cluster_network.api_server_port (cluster_endpoint_guard.tftest.hcl checks the endpoint after an apply)."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.control_plane_ingress_rules["kube_apiserver_from_load_balancer"].from_port == 7443 && aws_vpc_security_group_ingress_rule.api_load_balancer_ingress_rules["kube_apiserver_from_nodes"].to_port == 7443
    error_message = "the security group rules must open the overridden port."
  }
  assert {
    condition     = !contains(keys(aws_vpc_security_group_ingress_rule.control_plane_ingress_rules), "kube_apiserver_from_pods_192.168.0.0/16")
    error_message = "without pod CIDRs there is no pod rule."
  }
}

run "cluster_network_null_defaults_port" {
  command = plan

  variables {
    cluster_network = null
  }

  assert {
    condition     = output.exports.api.target_groups.kube_apiserver.port == 6443 && aws_lb_target_group.api_target_groups["kube_apiserver"].port == 6443
    error_message = "a null cluster_network must default the API port to 6443."
  }
}

run "public_requires_allowed_cidrs" {
  command = plan

  variables {
    api_load_balancer_public = true
  }

  expect_failures = [aws_lb.api_load_balancer]
}

run "public_with_allowed_cidrs" {
  command = plan

  variables {
    api_load_balancer_public  = true
    api_allowed_cidrs         = ["198.51.100.0/24"]
    api_load_balancer_subnets = { "us-east-1a" = "subnet-0ccc0000000000003", "us-east-1b" = "subnet-0ddd0000000000004" }
  }

  assert {
    condition     = !aws_lb.api_load_balancer[0].internal && aws_lb.api_load_balancer[0].subnets == toset(["subnet-0ccc0000000000003", "subnet-0ddd0000000000004"])
    error_message = "a public load balancer must be internet-facing in its own subnets."
  }
  assert {
    condition = toset(keys(aws_vpc_security_group_ingress_rule.api_load_balancer_ingress_rules)) == toset([
      "kube_apiserver_from_nodes",
      "kube_apiserver_from_198.51.100.0/24",
    ])
    error_message = "a public load balancer must admit exactly the nodes and the allowed CIDRs (the nodes' NAT addresses among them), not the VPC."
  }
}

run "rejects_public_in_node_subnets" {
  command = plan

  variables {
    api_load_balancer_public = true
    api_allowed_cidrs        = ["198.51.100.0/24"]
  }

  expect_failures = [aws_lb.api_load_balancer]
}

run "ipv6_pod_cidrs_skipped" {
  command = plan

  variables {
    cluster_network = { pods = ["192.168.0.0/16", "fd00:10:244::/56"], services = [], service_domain = null, api_server_port = 6443 }
  }

  assert {
    condition     = length([for k in keys(aws_vpc_security_group_ingress_rule.control_plane_ingress_rules) : k if startswith(k, "kube_apiserver_from_pods_")]) == 1
    error_message = "only IPv4 pod CIDRs become cidr_ipv4 rules."
  }
}

run "rejects_load_balancer_missing_zone" {
  command = plan

  variables {
    api_load_balancer_subnets = { "us-east-1a" = "subnet-0ccc0000000000003" }
  }

  expect_failures = [aws_lb.api_load_balancer]
}

run "rejects_unmatched_subnet" {
  command = plan

  override_data {
    target = data.aws_subnets.node_subnets
    values = {
      ids = []
    }
  }

  expect_failures = [aws_security_group.node_security_group]
}

run "rejects_unmatched_load_balancer_subnet" {
  command = plan

  variables {
    api_load_balancer_subnets = { "us-east-1a" = "subnet-0ccc0000000000003", "us-east-1b" = "subnet-0ddd0000000000004" }
  }

  override_data {
    target = data.aws_subnets.api_load_balancer_subnets
    values = {
      ids = []
    }
  }

  expect_failures = [aws_lb.api_load_balancer]
}

run "rejects_missing_vpc" {
  command = plan

  override_data {
    target = data.aws_vpcs.cluster_vpcs
    values = {
      ids = []
    }
  }

  expect_failures = [aws_security_group.node_security_group]
}

run "explicit_cidrs_skip_vpc_read" {
  command = plan

  variables {
    api_allowed_cidrs = ["10.20.0.0/16"]
  }

  assert {
    condition     = length(data.aws_vpc.cluster_vpc) == 0
    error_message = "with api_allowed_cidrs set, the VPC's CIDR must not be read."
  }
}

run "internal_defaults_to_vpc" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_ingress_rule.api_load_balancer_ingress_rules["kube_apiserver_from_10.0.0.0/16"].cidr_ipv4 == "10.0.0.0/16"
    error_message = "an internal load balancer must admit the VPC's primary CIDR when api_allowed_cidrs is empty."
  }
}

run "node_identity_policy_options" {
  command = plan

  variables {
    node_role_permissions_boundary = "arn:aws:iam::123456789012:policy/boundary"
    node_role_policy_arns          = { control_plane = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"] }
  }

  assert {
    condition     = aws_iam_role.node_roles["worker"].permissions_boundary == "arn:aws:iam::123456789012:policy/boundary"
    error_message = "the permissions boundary must apply to the created roles."
  }
  assert {
    condition     = keys(aws_iam_role_policy_attachment.node_role_policy_attachments) == ["control_plane/arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"] && aws_iam_role_policy_attachment.node_role_policy_attachments["control_plane/arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"].role == "captf-team-a-demo-1960e37c-control-plane"
    error_message = "node_role_policy_arns must attach each policy to its role only."
  }
}

run "rke2_adds_supervisor" {
  command = plan

  variables {
    distribution = "rke2"
  }

  assert {
    condition     = aws_lb_target_group.api_target_groups["rke2_supervisor"].port == 9345 && aws_lb_listener.api_listeners["rke2_supervisor"].port == 9345 && aws_lb_target_group.api_target_groups["rke2_supervisor"].name == "captf-team-a-demo-1960e37c-rke2"
    error_message = "RKE2 needs a supervisor listener and target group on 9345."
  }
  assert {
    condition     = output.exports.api.target_groups.rke2_supervisor.port == 9345
    error_message = "control-plane machines must find the supervisor target group in exports."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.control_plane_ingress_rules["rke2_supervisor_from_load_balancer"].from_port == 9345 && aws_vpc_security_group_ingress_rule.api_load_balancer_ingress_rules["rke2_supervisor_from_nodes"].from_port == 9345
    error_message = "the RKE2 supervisor must be reachable on 9345 through the load balancer."
  }
}

run "rke2_backend_is_6443" {
  command = plan

  variables {
    distribution    = "rke2"
    cluster_network = { pods = ["192.168.0.0/16"], services = [], service_domain = null, api_server_port = 7443 }
  }

  assert {
    condition     = aws_lb_listener.api_listeners["kube_apiserver"].port == 7443 && aws_lb_target_group.api_target_groups["kube_apiserver"].port == 6443
    error_message = "with RKE2 the endpoint port is api_server_port, but the kube-apiserver behind it always listens on 6443."
  }
  assert {
    condition     = output.exports.api.port == 7443 && output.exports.api.target_groups.kube_apiserver.port == 6443
    error_message = "exports must give the endpoint port and, per target group, the backend port machines register."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.control_plane_ingress_rules["kube_apiserver_from_load_balancer"].from_port == 6443 && aws_vpc_security_group_ingress_rule.control_plane_ingress_rules["kube_apiserver_from_pods_192.168.0.0/16"].from_port == 6443 && aws_vpc_security_group_ingress_rule.api_load_balancer_ingress_rules["kube_apiserver_from_nodes"].from_port == 7443
    error_message = "the control plane must open the backend port, the load balancer the endpoint port."
  }
}

run "rejects_supervisor_port_collision" {
  command = plan

  variables {
    distribution    = "rke2"
    cluster_network = { pods = [], services = [], service_domain = null, api_server_port = 9345 }
  }

  expect_failures = [aws_lb.api_load_balancer]
}

run "nodes_accept_each_other" {
  command = plan

  variables {
    ssh_allowed_cidrs = ["192.0.2.0/24"]
  }

  assert {
    condition     = toset(keys(aws_vpc_security_group_ingress_rule.node_ingress_rules)) == toset(["all_from_nodes", "ssh_from_192.0.2.0/24"])
    error_message = "the node group must admit all traffic from its own members and SSH from ssh_allowed_cidrs, nothing else."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.node_ingress_rules["all_from_nodes"].ip_protocol == "-1" && aws_vpc_security_group_ingress_rule.node_ingress_rules["ssh_from_192.0.2.0/24"].from_port == 22
    error_message = "node-to-node traffic must be every protocol; SSH port 22."
  }
  assert {
    condition     = aws_vpc_security_group_egress_rule.node_egress_rules["all"].ip_protocol == "-1" && aws_vpc_security_group_egress_rule.node_egress_rules["all"].cidr_ipv4 == "0.0.0.0/0"
    error_message = "nodes must keep outbound access: Terraform drops the default egress rule."
  }
  assert {
    condition     = toset(keys(aws_vpc_security_group_ingress_rule.control_plane_ingress_rules)) == toset(["kube_apiserver_from_load_balancer", "kube_apiserver_from_pods_192.168.0.0/16"])
    error_message = "the control-plane group must add only the API from the load balancer and the pods."
  }
}

run "happy_path" {
  assert {
    condition     = output.control_plane_endpoint == { host = aws_lb.api_load_balancer[0].dns_name, port = 6443 }
    error_message = "control_plane_endpoint must be the load balancer's DNS name on the API port."
  }
  assert {
    condition = output.failure_domains == [
      { name = "us-east-1a", control_plane = true, attributes = { subnet_id = "subnet-0aaa0000000000001" } },
      { name = "us-east-1b", control_plane = true, attributes = { subnet_id = "subnet-0bbb0000000000002" } },
    ]
    error_message = "failure_domains must list one control-plane domain per subnet zone, sorted by name."
  }
  assert {
    condition = output.exports == {
      schema                = "captf.io/aws-cluster/v1"
      region                = "us-east-1"
      vpc_id                = "vpc-0123456789abcdef0"
      kubernetes_cluster_id = "captf-team-a-demo-1960e37c"
      failure_domains = {
        "us-east-1a" = { subnet_id = "subnet-0aaa0000000000001" }
        "us-east-1b" = { subnet_id = "subnet-0bbb0000000000002" }
      }
      security_group_ids = {
        control_plane = [aws_security_group.control_plane_security_group[0].id, aws_security_group.node_security_group[0].id]
        worker        = [aws_security_group.node_security_group[0].id]
      }
      instance_profiles = {
        control_plane = "captf-team-a-demo-1960e37c-control-plane"
        worker        = "captf-team-a-demo-1960e37c-worker"
      }
      api = {
        host = aws_lb.api_load_balancer[0].dns_name
        port = 6443
        target_groups = {
          kube_apiserver = { arn = aws_lb_target_group.api_target_groups["kube_apiserver"].arn, port = 6443 }
        }
      }
      bootstrap_bucket = aws_s3_bucket.bootstrap_bucket[0].bucket
    }
    error_message = "exports must carry the region, network, security groups, instance profiles, target groups and bootstrap bucket."
  }
  assert {
    condition     = jsonencode(output.health) == jsonencode({ state = "running", healthy = true, message = "API load balancer captf-team-a-demo-1960e37c and bootstrap bucket present", reasons = [] })
    error_message = "health must be running and healthy while the load balancer and bucket exist."
  }
  assert {
    condition     = output.api_load_balancer_id == aws_lb.api_load_balancer[0].arn
    error_message = "api_load_balancer_id must be the load balancer's ARN."
  }
  assert {
    condition     = aws_lb.api_load_balancer[0].internal && aws_lb.api_load_balancer[0].load_balancer_type == "network" && aws_lb.api_load_balancer[0].name == "captf-team-a-demo-1960e37c"
    error_message = "the API load balancer must be an internal NLB named after the cluster."
  }
  assert {
    condition     = aws_lb.api_load_balancer[0].subnets == toset(["subnet-0aaa0000000000001", "subnet-0bbb0000000000002"]) && aws_lb.api_load_balancer[0].security_groups == toset([aws_security_group.api_load_balancer_security_group[0].id])
    error_message = "the API load balancer must use the node subnets and get its security group at creation."
  }
  assert {
    condition     = keys(aws_lb_target_group.api_target_groups) == ["kube_apiserver"] && aws_lb_target_group.api_target_groups["kube_apiserver"].name == "captf-team-a-demo-1960e37c-kapi"
    error_message = "kubeadm needs exactly one target group, for the API server."
  }
  assert {
    condition = alltrue([
      aws_lb_target_group.api_target_groups["kube_apiserver"].port == 6443,
      aws_lb_target_group.api_target_groups["kube_apiserver"].preserve_client_ip == "false",
      aws_lb_target_group.api_target_groups["kube_apiserver"].protocol == "TCP",
      aws_lb_target_group.api_target_groups["kube_apiserver"].vpc_id == "vpc-0123456789abcdef0",
      aws_lb_target_group.api_target_groups["kube_apiserver"].health_check[0].protocol == "TCP",
    ])
    error_message = "the API target group must be TCP on 6443 with client IP preservation off (hairpin) and TCP health checks."
  }
  assert {
    condition     = aws_lb_listener.api_listeners["kube_apiserver"].port == 6443 && aws_lb_listener.api_listeners["kube_apiserver"].default_action[0].target_group_arn == aws_lb_target_group.api_target_groups["kube_apiserver"].arn
    error_message = "the listener must forward the API port to the API target group."
  }
  assert {
    condition     = jsonencode(terraform_data.api_endpoint_guard[0].output) == jsonencode({ api_load_balancer_public = false, api_load_balancer_subnets = ["subnet-0aaa0000000000001", "subnet-0bbb0000000000002"], api_server_port = 6443 })
    error_message = "the endpoint guard must record the scheme, port and subnets the load balancer was created with."
  }
  assert {
    condition     = aws_s3_bucket.bootstrap_bucket[0].bucket_prefix == "captf-bootstrap-" && aws_s3_bucket.bootstrap_bucket[0].force_destroy
    error_message = "the bootstrap bucket must get a generated name and be destroyable with leftover objects."
  }
  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.bootstrap_bucket_public_access.block_public_acls,
      aws_s3_bucket_public_access_block.bootstrap_bucket_public_access.block_public_policy,
      aws_s3_bucket_public_access_block.bootstrap_bucket_public_access.ignore_public_acls,
      aws_s3_bucket_public_access_block.bootstrap_bucket_public_access.restrict_public_buckets,
    ])
    error_message = "every public access block setting must be on."
  }
  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.bootstrap_bucket_encryption.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "the bootstrap bucket must encrypt objects with SSE-S3."
  }
  assert {
    condition = jsondecode(aws_s3_bucket_policy.bootstrap_bucket_policy.policy).Statement == [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.bootstrap_bucket[0].arn, "${aws_s3_bucket.bootstrap_bucket[0].arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "ControlPlaneNodesReadPayloads"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.node_roles["control_plane"].arn }
        Action    = "s3:GetObject"
        Resource  = ["${aws_s3_bucket.bootstrap_bucket[0].arn}/control-plane/*"]
      },
      {
        Sid       = "WorkerNodesReadPayloads"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.node_roles["worker"].arn }
        Action    = "s3:GetObject"
        Resource  = ["${aws_s3_bucket.bootstrap_bucket[0].arn}/worker/*", "${aws_s3_bucket.bootstrap_bucket[0].arn}/pool/*"]
      },
      {
        Sid       = "DenyWorkerNodesControlPlanePayloads"
        Effect    = "Deny"
        Principal = { AWS = aws_iam_role.node_roles["worker"].arn }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.bootstrap_bucket[0].arn}/control-plane/*"
      },
    ]
    error_message = "the bucket policy must deny plain HTTP, let each node role read its own key prefixes, and deny workers the control-plane payloads."
  }
  assert {
    condition     = jsondecode(aws_iam_role.node_roles["worker"].assume_role_policy).Statement[0].Principal == { Service = "ec2.amazonaws.com" } && aws_iam_role.node_roles["worker"].path == "/captf/"
    error_message = "the node roles must trust EC2 in the current partition and live under /captf/."
  }
  assert {
    condition     = contains(jsondecode(aws_iam_role_policy.node_role_policies["control_plane"].policy).Statement[0].Action, "elasticloadbalancing:RegisterTargets") && !contains(jsondecode(aws_iam_role_policy.node_role_policies["worker"].policy).Statement[0].Action, "ec2:CreateVolume")
    error_message = "the control-plane role must carry the cloud controller manager's policy and the worker role the node policy only."
  }
  assert {
    condition     = aws_iam_instance_profile.node_instance_profiles["control_plane"].role == aws_iam_role.node_roles["control_plane"].name && length(aws_iam_role_policy_attachment.node_role_policy_attachments) == 0
    error_message = "each instance profile must hold its role, and no managed policy is attached by default."
  }
}

run "tags_on_taggable_resources" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for tags in concat(
        [
          aws_lb.api_load_balancer[0].tags,
          aws_security_group.node_security_group[0].tags,
          aws_security_group.control_plane_security_group[0].tags,
          aws_security_group.api_load_balancer_security_group[0].tags,
          aws_s3_bucket.bootstrap_bucket[0].tags,
        ],
        [for r in aws_lb_target_group.api_target_groups : r.tags],
        [for r in aws_lb_listener.api_listeners : r.tags],
        [for r in aws_vpc_security_group_ingress_rule.node_ingress_rules : r.tags],
        [for r in aws_vpc_security_group_egress_rule.node_egress_rules : r.tags],
        [for r in aws_vpc_security_group_ingress_rule.control_plane_ingress_rules : r.tags],
        [for r in aws_vpc_security_group_ingress_rule.api_load_balancer_ingress_rules : r.tags],
        [for r in aws_vpc_security_group_egress_rule.api_load_balancer_egress_rules : r.tags],
        [for r in aws_iam_role.node_roles : r.tags],
        [for r in aws_iam_instance_profile.node_instance_profiles : r.tags],
      ) : [for k, v in merge(var.captf_tags, var.additional_tags) : lookup(tags, k, null) == v]
    ]))
    error_message = "every taggable resource must carry the captf tags and additional_tags."
  }
  assert {
    condition     = aws_security_group.node_security_group[0].tags["kubernetes.io/cluster/captf-team-a-demo-1960e37c"] == "owned"
    error_message = "the node security group must carry the cluster ownership tag."
  }
  assert {
    condition = alltrue([
      for tags in [aws_security_group.control_plane_security_group[0].tags, aws_security_group.api_load_balancer_security_group[0].tags, aws_lb.api_load_balancer[0].tags] :
      !contains(keys(tags), "kubernetes.io/cluster/captf-team-a-demo-1960e37c")
    ])
    error_message = "only the node security group may carry the cluster ownership tag: cloud-provider-aws fails on two tagged groups per instance."
  }
}

# A second identical apply: nothing is replaced, so every id in the outputs
# (security groups, bucket, load balancer DNS name) is unchanged.
run "reapply_is_stable" {
  # Passed in as test-only variables: OpenTofu does not resolve run.<name>
  # inside an assert.
  variables {
    previous_exports  = run.happy_path.exports
    previous_endpoint = run.happy_path.control_plane_endpoint
  }

  assert {
    condition     = jsonencode(output.exports) == jsonencode(var.previous_exports)
    error_message = "a second apply must keep every exported id."
  }
  assert {
    condition     = jsonencode(output.control_plane_endpoint) == jsonencode(var.previous_endpoint)
    error_message = "a second apply must keep the endpoint."
  }
}

run "tag_change_keeps_ids" {
  # previous_* are test-only: OpenTofu resolves run.<name> neither inside an
  # assert nor for an apply older than the last one.
  variables {
    additional_tags   = { team = "platform", cost-center = "1234" }
    previous_exports  = run.reapply_is_stable.exports
    previous_endpoint = run.reapply_is_stable.control_plane_endpoint
  }

  assert {
    condition     = jsonencode(output.exports) == jsonencode(var.previous_exports) && jsonencode(output.control_plane_endpoint) == jsonencode(var.previous_endpoint)
    error_message = "a tag change must update resources in place: every id and the endpoint stay."
  }
  assert {
    condition     = aws_lb.api_load_balancer[0].tags["cost-center"] == "1234"
    error_message = "the new tag must reach the resources."
  }
}

# Applies on top of the state above: switching to brought identities, then
# to a user endpoint, replaces what the module created.
run "node_identity_byo" {
  variables {
    control_plane_instance_profile = { name = "platform-cp", role_arn = "arn:aws:iam::123456789012:role/platform/cp" }
    worker_instance_profile        = { name = "platform-worker", role_arn = "arn:aws:iam::123456789012:role/platform/worker" }
  }

  assert {
    condition     = length(aws_iam_role.node_roles) == 0 && length(aws_iam_instance_profile.node_instance_profiles) == 0 && length(aws_iam_role_policy.node_role_policies) == 0
    error_message = "brought instance profiles must replace the module's roles and profiles."
  }
  assert {
    condition     = output.exports.instance_profiles == { control_plane = "platform-cp", worker = "platform-worker" }
    error_message = "exports must name the brought instance profiles."
  }
  assert {
    condition     = jsondecode(aws_s3_bucket_policy.bootstrap_bucket_policy.policy).Statement[1].Principal == { AWS = "arn:aws:iam::123456789012:role/platform/cp" } && jsondecode(aws_s3_bucket_policy.bootstrap_bucket_policy.policy).Statement[3].Principal == { AWS = "arn:aws:iam::123456789012:role/platform/worker" }
    error_message = "the bucket policy must grant the brought profiles' roles, so they need no S3 permission of their own."
  }
}

run "user_endpoint_skips_load_balancer" {
  variables {
    control_plane_endpoint = { host = "api.demo.example.com", port = 443 }
  }

  assert {
    condition     = length(aws_lb.api_load_balancer) == 0 && length(aws_lb_target_group.api_target_groups) == 0 && length(aws_lb_listener.api_listeners) == 0 && length(aws_security_group.api_load_balancer_security_group) == 0 && length(terraform_data.api_endpoint_guard) == 0
    error_message = "a user endpoint must skip the load balancer, its target groups, listeners, security group and guard."
  }
  assert {
    condition     = output.control_plane_endpoint == { host = "api.demo.example.com", port = 443 }
    error_message = "a user endpoint must be passed through."
  }
  assert {
    condition     = output.exports.api == null
    error_message = "exports.api must be null when there is nothing to register in."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.control_plane_ingress_rules["kube_apiserver_from_10.0.0.0/16"].cidr_ipv4 == "10.0.0.0/16" && aws_vpc_security_group_ingress_rule.control_plane_ingress_rules["kube_apiserver_from_10.0.0.0/16"].from_port == 6443
    error_message = "without the module's load balancer, the allowed networks (the VPC by default) must reach the API port on the control plane directly."
  }
  assert {
    condition     = jsonencode(output.health) == jsonencode({ state = "running", healthy = true, message = "bootstrap bucket present; the API endpoint is user-supplied", reasons = [] })
    error_message = "health must not depend on a load balancer the module does not own."
  }
}
