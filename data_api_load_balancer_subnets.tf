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

# The API load balancer's own subnets, when api_load_balancer_subnets names
# them, read like the node subnets (data_node_subnets.tf); the precondition
# on aws_lb.api_load_balancer reports one that does not match.
data "aws_subnets" "api_load_balancer_subnets" {
  for_each = var.api_load_balancer_subnets

  filter {
    name   = "subnet-id"
    values = [each.value]
  }
  filter {
    name   = "availability-zone"
    values = [each.key]
  }
  filter {
    name   = "vpc-id"
    values = [coalesce(var.vpc_id, "-")]
  }
}
