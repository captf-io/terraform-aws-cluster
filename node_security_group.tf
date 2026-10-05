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

# Attached to every node, control plane and workers alike, and the only group
# tagged kubernetes.io/cluster/<id> = owned: the cloud controller manager
# adds Service load balancer rules to exactly one tagged group per instance
# (findSecurityGroupForInstance in cloud-provider-aws v1.36.1). Always
# created, so it holds the check of the node subnets.
resource "aws_security_group" "node_security_group" {
  # count = 1, not a bare resource: once a refresh drops a bare resource
  # from state its references read as unknown, which try() cannot catch, so
  # exports would go null; an empty tuple fails the index, and try() falls
  # back (DESIGN.md decision 10).
  count = 1

  description = "CAPTF nodes of cluster ${local.cluster_key}"
  name        = local.security_group_names.node
  # The cloud controller manager adds ingress rules for Service load
  # balancers to this group; revoking every rule first lets destroy delete
  # it even when one of them references a group the manager left behind.
  revoke_rules_on_delete = true
  tags                   = merge(local.tags, local.cluster_ownership_tags, { Name = local.security_group_names.node })
  vpc_id                 = local.vpc_id

  lifecycle {
    precondition {
      condition     = length(data.aws_vpcs.cluster_vpcs.ids) == 1
      error_message = "vpc_id names ${coalesce(var.vpc_id, "-")}, which is not a VPC in this account and region."
    }
    precondition {
      condition     = length(local.unmatched_node_subnets) == 0
      error_message = "subnets maps zones to subnets that are not in that zone or not in vpc_id ${coalesce(var.vpc_id, "-")}: ${join(", ", local.unmatched_node_subnets)}."
    }
  }
}
