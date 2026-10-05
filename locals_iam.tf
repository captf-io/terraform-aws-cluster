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

# Node identities: an IAM role and instance profile for control-plane nodes
# and one for workers, unless control_plane_instance_profile or worker_instance_profile brings an existing one.
#
# The policies are built with jsonencode(), not aws_iam_policy_document: a
# mocked data source returns a random string, and the tests assert the
# policies. The statements are the "Control Plane Policy" and "Node Policy"
# of cloud-provider-aws v1.36.1
# (https://github.com/kubernetes/cloud-provider-aws/blob/v1.36.1/docs/prerequisites.md),
# which the cloud controller manager and the kubelet's ECR credential
# provider need: workers get the Node Policy, control-plane nodes both. Reading the bootstrap payloads is granted by the bucket
# policy instead (locals_bootstrap.tf), the same way for created and brought
# identities.
locals {
  # Each node identity is created unless brought, independently.
  brought_instance_profiles = {
    control_plane = var.control_plane_instance_profile
    worker        = var.worker_instance_profile
  }

  node_role_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EC2AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.${data.aws_partition.current_partition.dns_suffix}" }
      Action    = "sts:AssumeRole"
    }]
  })

  node_policy_statement = {
    Sid    = "NodeAndEcrPull"
    Effect = "Allow"
    Action = [
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:DescribeRepositories",
      "ecr:GetAuthorizationToken",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:ListImages",
    ]
    Resource = "*"
  }

  control_plane_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "CloudControllerManager"
      Effect = "Allow"
      Action = [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeTags",
        "ec2:AttachVolume",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:CreateRoute",
        "ec2:CreateSecurityGroup",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:DeleteRoute",
        "ec2:DeleteSecurityGroup",
        "ec2:DeleteVolume",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeInstanceTopology",
        "ec2:DescribeInstances",
        "ec2:DescribeRegions",
        "ec2:DescribeRouteTables",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeVolumes",
        "ec2:DescribeVpcs",
        "ec2:DetachVolume",
        "ec2:ModifyInstanceAttribute",
        "ec2:ModifyVolume",
        "ec2:RevokeSecurityGroupIngress",
        "elasticloadbalancing:AddTags",
        "elasticloadbalancing:ApplySecurityGroupsToLoadBalancer",
        "elasticloadbalancing:AttachLoadBalancerToSubnets",
        "elasticloadbalancing:ConfigureHealthCheck",
        "elasticloadbalancing:CreateListener",
        "elasticloadbalancing:CreateLoadBalancer",
        "elasticloadbalancing:CreateLoadBalancerListeners",
        "elasticloadbalancing:CreateLoadBalancerPolicy",
        "elasticloadbalancing:CreateTargetGroup",
        "elasticloadbalancing:DeleteListener",
        "elasticloadbalancing:DeleteLoadBalancer",
        "elasticloadbalancing:DeleteLoadBalancerListeners",
        "elasticloadbalancing:DeleteTargetGroup",
        "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
        "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:DescribeListeners",
        "elasticloadbalancing:DescribeLoadBalancerAttributes",
        "elasticloadbalancing:DescribeLoadBalancerPolicies",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeTargetHealth",
        "elasticloadbalancing:DetachLoadBalancerFromSubnets",
        "elasticloadbalancing:ModifyListener",
        "elasticloadbalancing:ModifyLoadBalancerAttributes",
        "elasticloadbalancing:ModifyTargetGroup",
        "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
        "elasticloadbalancing:RegisterTargets",
        "elasticloadbalancing:SetLoadBalancerPoliciesForBackendServer",
        "elasticloadbalancing:SetLoadBalancerPoliciesOfListener",
        "iam:CreateServiceLinkedRole",
        "kms:DescribeKey",
      ]
      Resource = "*"
      },
      # The Node Policy too: the kubelet of a control-plane node pulls
      # images and reads its instance like any other.
      local.node_policy_statement,
    ]
  })

  worker_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [local.node_policy_statement]
  })

  node_role_definitions = {
    control_plane = {
      name        = "${local.name_prefix}-control-plane"
      description = "CAPTF control-plane nodes of cluster ${local.cluster_key}"
      policy      = local.control_plane_policy
    }
    worker = {
      name        = "${local.name_prefix}-worker"
      description = "CAPTF worker nodes of cluster ${local.cluster_key}"
      policy      = local.worker_policy
    }
  }
  node_roles = { for k, r in local.node_role_definitions : k => r if local.brought_instance_profiles[k] == null }

  # "<role>/<policy ARN>" -> attachment, for the roles the module creates.
  node_role_policy_attachments = {
    for a in flatten([
      for role in keys(local.node_roles) : [
        for arn in var.node_role_policy_arns[role] : { role = role, policy_arn = arn }
      ]
    ]) : "${a.role}/${a.policy_arn}" => a
  }

  # The instance profile and role ARN of each node identity, created or
  # brought.
  node_instance_profile_names = {
    for k in keys(local.node_role_definitions) : k => (
      local.brought_instance_profiles[k] == null ? try(aws_iam_instance_profile.node_instance_profiles[k].name, null) : local.brought_instance_profiles[k].name
    )
  }
  node_role_arns = {
    for k in keys(local.node_role_definitions) : k => (
      local.brought_instance_profiles[k] == null ? aws_iam_role.node_roles[k].arn : local.brought_instance_profiles[k].role_arn
    )
  }
}
