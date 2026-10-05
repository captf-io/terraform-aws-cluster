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

# Records, when the API load balancer is created, every input that decides
# the endpoint: the scheme, the port and the subnets (CONVENTIONS.md section
# 12). ignore_changes keeps the recorded value, and the postcondition fails
# any later plan that would change one, whether the change would replace
# the load balancer (scheme, a removed subnet) or move the endpoint in place
# (port): a new endpoint breaks every kubeconfig, and CAPI never updates
# Cluster.spec.controlPlaneEndpoint
# (https://captf.io/docs/module-author/contract/v1alpha1/cluster.html
# "control_plane_endpoint (output)"). CAPTF's destructive-plan guard catches
# replacements only, and an operator can approve those. Unlike
# prevent_destroy, this does not block deleting the cluster. Subnets may be
# added (in place for a Network Load Balancer); only the subnets recorded
# at creation are protected.
resource "terraform_data" "api_endpoint_guard" {
  count = local.api_load_balancer_enabled ? 1 : 0

  input = local.api_endpoint_settings

  lifecycle {
    ignore_changes = [input]

    postcondition {
      condition = alltrue([
        self.output.api_load_balancer_public == var.api_load_balancer_public,
        self.output.api_server_port == local.api_server_port,
        length(setsubtract(self.output.api_load_balancer_subnets, local.api_load_balancer_subnet_ids)) == 0,
      ])
      error_message = "The API endpoint of this cluster is fixed once its load balancer exists: ${join("; ", compact([
        self.output.api_load_balancer_public == var.api_load_balancer_public ? "" : "api_load_balancer_public cannot change (recorded ${self.output.api_load_balancer_public}, requested ${var.api_load_balancer_public})",
        self.output.api_server_port == local.api_server_port ? "" : "cluster_network.api_server_port cannot change (recorded ${self.output.api_server_port}, requested ${local.api_server_port})",
        length(setsubtract(self.output.api_load_balancer_subnets, local.api_load_balancer_subnet_ids)) == 0 ? "" : "api_load_balancer_subnets cannot lose a subnet (recorded ${join(", ", self.output.api_load_balancer_subnets)}, requested ${join(", ", local.api_load_balancer_subnet_ids)})",
      ]))}. Revert the change, or create a new cluster."
    }
  }
}
