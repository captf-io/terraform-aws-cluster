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

# The Kubernetes API endpoint: a Network Load Balancer, internal unless
# api_load_balancer_public. Its DNS name is the control_plane_endpoint host
# and stays the same for the load balancer's life.
resource "aws_lb" "api_load_balancer" {
  count = local.api_load_balancer_enabled ? 1 : 0

  enable_cross_zone_load_balancing = true
  # Cluster deletion destroys it: the destructive-plan guard and
  # api_endpoint_guard stop an accidental replacement instead.
  enable_deletion_protection = false
  internal                   = !var.api_load_balancer_public
  ip_address_type            = "ipv4"
  load_balancer_type         = "network"
  name                       = local.api_load_balancer_name
  security_groups            = [aws_security_group.api_load_balancer_security_group[0].id]
  subnets                    = local.api_load_balancer_subnet_ids
  tags                       = local.tags

  lifecycle {
    precondition {
      condition     = !var.api_load_balancer_public || length(var.api_allowed_cidrs) > 0
      error_message = "api_allowed_cidrs must list the networks allowed to reach an internet-facing API load balancer, the nodes' public egress addresses (the NAT gateways' Elastic IPs as /32s) among them: its DNS name resolves to public addresses, so the nodes' own traffic, the first control-plane node's included, arrives from those."
    }
    precondition {
      condition     = !var.api_load_balancer_public || length(var.api_load_balancer_subnets) > 0
      error_message = "api_load_balancer_subnets must name public subnets for an internet-facing API load balancer: the node subnets are usually private, an NLB in them is unreachable from outside, and its subnets can never be removed later."
    }
    precondition {
      condition     = length(local.unmatched_api_load_balancer_subnets) == 0
      error_message = "api_load_balancer_subnets names subnets that are not in their zone or not in vpc_id ${coalesce(var.vpc_id, "-")}: ${join(", ", local.unmatched_api_load_balancer_subnets)}."
    }
    precondition {
      condition     = length(local.api_load_balancer_missing_zones) == 0
      error_message = "api_load_balancer_subnets has no subnet in ${join(", ", local.api_load_balancer_missing_zones)}: a Network Load Balancer sends no traffic to targets in a zone it is not in, so control-plane nodes there would never serve the API. Add a subnet for every zone of subnets."
    }
    precondition {
      condition     = !(var.distribution == "rke2" && local.api_server_port == local.rke2_supervisor_port)
      error_message = "cluster_network.api_server_port must not be ${local.rke2_supervisor_port} with distribution rke2: the RKE2 supervisor listens on that port of the endpoint."
    }
  }
}
