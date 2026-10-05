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

# The VPC named by vpc_id, as a listing: it returns no ID, rather than
# failing, once the VPC is gone, so a destroy (which reads data sources too)
# still runs after the network was deleted (CONVENTIONS.md section 9). The
# precondition on aws_security_group.node_security_group reports a vpc_id
# that names no VPC when it matters, at plan time.
data "aws_vpcs" "cluster_vpcs" {
  filter {
    name   = "vpc-id"
    values = [coalesce(var.vpc_id, "-")]
  }
}
