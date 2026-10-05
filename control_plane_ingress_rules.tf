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

# Control-plane ingress: the API (and RKE2 supervisor) ports from the load
# balancer, the nodes and the pods, and etcd between control-plane nodes
# (locals_security_groups.tf). Control-plane nodes get their egress from the
# node group they also carry.
resource "aws_vpc_security_group_ingress_rule" "control_plane_ingress_rules" {
  for_each = local.control_plane_ingress_rules

  cidr_ipv4                    = each.value.cidr_ipv4
  description                  = each.value.description
  from_port                    = each.value.from_port
  ip_protocol                  = each.value.ip_protocol
  referenced_security_group_id = each.value.referenced_security_group_id
  security_group_id            = aws_security_group.control_plane_security_group[0].id
  tags                         = local.tags
  to_port                      = each.value.to_port
}
