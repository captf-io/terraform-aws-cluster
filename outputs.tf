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

# Contract outputs of the cluster role, in contract order:
# https://captf.io/docs/module-author/contract/v1alpha1/cluster.html#outputs
# and "health" in https://captf.io/docs/module-author/contract/v1alpha1/common.html

output "control_plane_endpoint" {
  description = "The API endpoint: the load balancer's DNS name and the API port, or the user's endpoint passed through. Stable for the cluster's life."
  # try(): a load balancer deleted out of band leaves state on refresh; the
  # output is then null, never half-set.
  value = local.api_load_balancer_enabled ? try({ host = aws_lb.api_load_balancer[0].dns_name, port = local.api_server_port }, null) : var.control_plane_endpoint
}

output "failure_domains" {
  description = "One failure domain per availability zone of the node subnets, every one eligible for control-plane machines."
  value = [
    for z in sort(keys(local.failure_domains)) : {
      name          = z
      control_plane = true
      attributes    = local.failure_domains[z]
    }
  ]
}

output "exports" {
  description = "Handed to machines and pools as captf_cluster_outputs; schema captf.io/aws-cluster/v1 (README \"Exports\")."
  value       = local.exports
}

output "health" {
  description = "running while the API load balancer and the bootstrap bucket exist; degraded, with a reason each, when one was deleted out of band."
  value       = local.health_reading
}
