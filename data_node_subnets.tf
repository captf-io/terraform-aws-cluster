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

# The node subnets the user brings, one read per availability zone with the
# subnet, its zone and the VPC as filters. aws_subnets returns no ID rather
# than failing when nothing matches, so a destroy, which reads data sources
# too, still runs after a subnet is gone; the precondition on
# aws_security_group.node_security_group rejects a subnet mapped to the
# wrong zone or VPC when it matters, at plan time.
data "aws_subnets" "node_subnets" {
  for_each = var.subnets == null ? tomap({}) : var.subnets

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
