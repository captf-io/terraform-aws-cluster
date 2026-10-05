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

# Security group rules, one keyed map per group and direction. Each rule is
# its own aws_vpc_security_group_*_rule, so a rule the cloud controller
# manager adds for a Service never shows as drift and adding a rule never
# replaces another
# (https://registry.terraform.io/providers/hashicorp/aws/6.67.0/docs/resources/security_group).
#
# Every rule names exactly one source or destination: cidr_ipv4 or
# referenced_security_group_id; the other is null.
locals {
  node_security_group_id          = aws_security_group.node_security_group[0].id
  control_plane_security_group_id = aws_security_group.control_plane_security_group[0].id

  # Nodes of one cluster accept all traffic from each other, scoped to the
  # node group every node carries (control-plane nodes included), so any
  # CNI, webhook or etcd peer works without port lists (CONVENTIONS.md
  # section 8). Beyond that only SSH from ssh_allowed_cidrs.
  node_ingress_rules = merge(
    {
      all_from_nodes = {
        description                  = "All traffic between the cluster's nodes"
        ip_protocol                  = "-1"
        from_port                    = null
        to_port                      = null
        cidr_ipv4                    = null
        referenced_security_group_id = local.node_security_group_id
      }
    },
    {
      for c in var.ssh_allowed_cidrs : "ssh_from_${c}" => {
        description                  = "SSH from an allowed network"
        ip_protocol                  = "tcp"
        from_port                    = 22
        to_port                      = 22
        cidr_ipv4                    = c
        referenced_security_group_id = null
      }
    },
  )

  # The API (and RKE2 supervisor) backend ports, from what fronts the
  # control plane. Traffic between nodes is already open (above).
  control_plane_ingress_rules = merge(
    # With client IP preservation off, the load balancer connects from its
    # own addresses, which its security group stands for.
    {
      for k, p in local.api_load_balancer_ports : "${k}_from_load_balancer" => {
        description                  = "${p.description} from the API load balancer"
        ip_protocol                  = "tcp"
        from_port                    = p.backend_port
        to_port                      = p.backend_port
        cidr_ipv4                    = null
        referenced_security_group_id = aws_security_group.api_load_balancer_security_group[0].id
      }
    },
    # Pods reach the API server directly through the kubernetes Service; with
    # a native-routing CNI their source is the pod address. IPv4 only: the
    # rules carry cidr_ipv4, and a dual-stack list also holds an IPv6 CIDR.
    {
      for c in try(coalesce(var.cluster_network.pods, []), []) : "kube_apiserver_from_pods_${c}" => {
        description                  = "kube-apiserver from pods"
        ip_protocol                  = "tcp"
        from_port                    = local.api_backend_port
        to_port                      = local.api_backend_port
        cidr_ipv4                    = c
        referenced_security_group_id = null
      } if can(cidrnetmask(c))
    },
    # Without the module's load balancer, whatever fronts the user's endpoint
    # connects from api_allowed_cidrs straight to the control plane.
    {
      for x in setproduct(keys(local.api_ports), local.api_allowed_cidrs) : "${x[0]}_from_${x[1]}" => {
        description                  = "${local.api_ports[x[0]].description} from an allowed network"
        ip_protocol                  = "tcp"
        from_port                    = local.api_ports[x[0]].backend_port
        to_port                      = local.api_ports[x[0]].backend_port
        cidr_ipv4                    = x[1]
        referenced_security_group_id = null
      } if !local.api_load_balancer_enabled
    },
  )

  # Nodes need the internet or VPC endpoints for images and AWS APIs; the
  # network the user brings (routes, NAT, firewalls) decides what is
  # reachable.
  node_egress_rules = {
    all = {
      description                  = "All outbound traffic"
      ip_protocol                  = "-1"
      from_port                    = null
      to_port                      = null
      cidr_ipv4                    = "0.0.0.0/0"
      referenced_security_group_id = null
    }
  }

  # Clients of the endpoint: every node (control-plane nodes reach the
  # endpoint they are registered behind, the hairpin the contract requires)
  # and the allowed networks (the management cluster among them). An
  # internet-facing endpoint resolves to public addresses, so node traffic
  # then arrives from their public egress addresses, which
  # api_allowed_cidrs must list.
  api_load_balancer_ingress_rules = merge(
    {
      for k, p in local.api_load_balancer_ports : "${k}_from_nodes" => {
        description                  = "${p.description} from every node"
        ip_protocol                  = "tcp"
        from_port                    = p.listener_port
        to_port                      = p.listener_port
        cidr_ipv4                    = null
        referenced_security_group_id = local.node_security_group_id
      }
    },
    {
      for x in setproduct(keys(local.api_load_balancer_ports), local.api_allowed_cidrs) : "${x[0]}_from_${x[1]}" => {
        description                  = "${local.api_ports[x[0]].description} from an allowed network"
        ip_protocol                  = "tcp"
        from_port                    = local.api_ports[x[0]].listener_port
        to_port                      = local.api_ports[x[0]].listener_port
        cidr_ipv4                    = x[1]
        referenced_security_group_id = null
      }
    },
  )

  # Traffic and health checks to the targets, on the backend ports.
  api_load_balancer_egress_rules = {
    for k, p in local.api_load_balancer_ports : "${k}_to_control_plane" => {
      description                  = "${p.description} to control-plane nodes"
      ip_protocol                  = "tcp"
      from_port                    = p.backend_port
      to_port                      = p.backend_port
      cidr_ipv4                    = null
      referenced_security_group_id = local.control_plane_security_group_id
    }
  }
}
