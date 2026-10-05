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

# The Kubernetes API endpoint: a Network Load Balancer unless the endpoint
# comes from elsewhere (https://captf.io/docs/module-author/contract/v1alpha1/cluster.html
# "control_plane_endpoint").
locals {
  # Non-null means "use this endpoint, don't create one": the user or a
  # control-plane provider owns it.
  api_load_balancer_enabled = var.control_plane_endpoint == null

  # The endpoint port is cluster_network.api_server_port ?? 6443. Behind it,
  # kubeadm's kube-apiserver binds that port too (templates keep bindPort
  # equal), while RKE2's always listens on 6443 (CONVENTIONS.md section 12,
  # control-planes/rke2.md).
  api_server_port      = coalesce(try(var.cluster_network.api_server_port, null), 6443)
  api_backend_port     = var.distribution == "rke2" ? 6443 : local.api_server_port
  rke2_supervisor_port = 9345

  # One listener and one target group per port: the listener on the
  # endpoint port, the target group on the backend port. RKE2 joins through
  # the supervisor on 9345 of the same host as the endpoint.
  api_port_definitions = {
    kube_apiserver = {
      description      = "kube-apiserver"
      listener_port    = local.api_server_port
      backend_port     = local.api_backend_port
      name_suffix      = "kapi"
      distribution_any = true
    }
    rke2_supervisor = {
      description      = "RKE2 supervisor"
      listener_port    = local.rke2_supervisor_port
      backend_port     = local.rke2_supervisor_port
      name_suffix      = "rke2"
      distribution_any = false
    }
  }
  api_ports = {
    for k, p in local.api_port_definitions : k => p
    if p.distribution_any || var.distribution == "rke2"
  }
  # The ports that get a listener and a target group: none with a user
  # endpoint.
  api_load_balancer_ports = { for k, p in local.api_ports : k => p if local.api_load_balancer_enabled }

  # Zone -> subnet of the load balancer: its own subnets, else the nodes'.
  api_load_balancer_subnets = length(var.api_load_balancer_subnets) > 0 ? var.api_load_balancer_subnets : (var.subnets == null ? tomap({}) : var.subnets)
  unmatched_api_load_balancer_subnets = sort([
    for z, read in data.aws_subnets.api_load_balancer_subnets : "${z}: ${var.api_load_balancer_subnets[z]}" if length(read.ids) != 1
  ])
  api_load_balancer_subnet_ids = sort(values(local.api_load_balancer_subnets))
  # Node zones the load balancer has no subnet in: its targets there would
  # never receive traffic.
  api_load_balancer_missing_zones = sort(setsubtract(keys(local.failure_domains), keys(local.api_load_balancer_subnets)))

  # Who may reach the API besides the nodes. An internet-facing load balancer
  # gets exactly the list the user gives, which must include the nodes' own
  # public egress addresses (the precondition on aws_lb.api_load_balancer
  # rejects an empty list); an internal one defaults to the VPC.
  api_allowed_cidrs = (
    length(var.api_allowed_cidrs) > 0 ? var.api_allowed_cidrs :
    var.api_load_balancer_public ? [] : [for v in data.aws_vpc.cluster_vpc : v.cidr_block]
  )

  # Every input that decides the endpoint, recorded by
  # terraform_data.api_endpoint_guard when the load balancer is created.
  api_endpoint_settings = {
    api_load_balancer_public  = var.api_load_balancer_public
    api_server_port           = local.api_server_port
    api_load_balancer_subnets = local.api_load_balancer_subnet_ids
  }
}
