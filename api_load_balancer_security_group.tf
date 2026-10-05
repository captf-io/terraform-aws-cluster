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

# The API load balancer's security group. It must exist when the load
# balancer is created: a Network Load Balancer created without security
# groups can never get one
# (https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-security-groups.html).
resource "aws_security_group" "api_load_balancer_security_group" {
  count = local.api_load_balancer_enabled ? 1 : 0

  description = "CAPTF API load balancer of cluster ${local.cluster_key}"
  name        = local.security_group_names.api_load_balancer
  tags        = merge(local.tags, { Name = local.security_group_names.api_load_balancer })
  vpc_id      = local.vpc_id
}
