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

# The VPC's primary CIDR, the default network allowed to reach an internal
# API endpoint. Read only when that default applies and the VPC exists
# (data_cluster_vpcs.tf), so this singular read never runs against a VPC
# that is gone.
data "aws_vpc" "cluster_vpc" {
  count = length(var.api_allowed_cidrs) == 0 && !var.api_load_balancer_public && length(data.aws_vpcs.cluster_vpcs.ids) == 1 ? 1 : 0

  id = var.vpc_id
}
