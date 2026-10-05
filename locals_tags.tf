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

# Tags for every taggable resource (CONVENTIONS.md section 7). AWS accepts the
# captf.io/<key> keys unchanged; they merge last so additional_tags cannot
# override them.
locals {
  captf_tags = { for k, v in var.captf_tags : k => v }

  # Empty in the cluster role on purpose: cloud-provider-aws fails with
  # "Multiple tagged security groups found for instance" when more than one
  # of an instance's security groups carries kubernetes.io/cluster/<id>
  # (findSecurityGroupForInstance in cloud-provider-aws v1.36.1), so only the
  # node security group gets cluster_ownership_tags.
  cloud_tags = {}

  tags = merge(var.additional_tags, local.cloud_tags, local.captf_tags)

  cluster_ownership_tags = {
    "kubernetes.io/cluster/${local.kubernetes_cluster_id}" = "owned"
  }
}
