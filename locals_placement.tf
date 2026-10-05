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

# Failure domains: one per availability zone of the node subnets
# (https://captf.io/docs/module-author/contract/v1alpha1/cluster.html
# "failure_domains"). Machines and pools find each zone's subnet through
# exports.
locals {
  vpc_id = var.vpc_id

  # Zone -> attributes, the shape both the failure_domains output and
  # exports.failure_domains use. Every attribute is a string
  # (FailureDomain.attributes is map[string]string).
  failure_domains = { for z, s in(var.subnets == null ? tomap({}) : var.subnets) : z => { subnet_id = s } }

  # Subnets AWS does not find in their zone and the VPC: "<zone>: <subnet>".
  unmatched_node_subnets = sort([for z, read in data.aws_subnets.node_subnets : "${z}: ${var.subnets[z]}" if length(read.ids) != 1])
}
