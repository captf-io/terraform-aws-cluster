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

# The node IAM roles, one for control-plane nodes and one for workers, unless
# control_plane_instance_profile or worker_instance_profile brings an
# existing one (locals_iam.tf). The /captf/ path keeps them apart from the
# account's other roles.
resource "aws_iam_role" "node_roles" {
  for_each = local.node_roles

  assume_role_policy   = local.node_role_trust_policy
  description          = each.value.description
  name                 = each.value.name
  path                 = "/captf/"
  permissions_boundary = var.node_role_permissions_boundary
  tags                 = local.tags
}
