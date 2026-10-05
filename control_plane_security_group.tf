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

# Attached to control-plane nodes only: the API server, the RKE2 supervisor
# and etcd. Not cluster-tagged (see node_security_group.tf).
resource "aws_security_group" "control_plane_security_group" {
  # count = 1, not a bare resource: once a refresh drops a bare resource
  # from state its references read as unknown, which try() cannot catch, so
  # exports would go null; an empty tuple fails the index, and try() falls
  # back (DESIGN.md decision 10).
  count = 1

  description = "CAPTF control-plane nodes of cluster ${local.cluster_key}"
  name        = local.security_group_names.control_plane
  tags        = merge(local.tags, { Name = local.security_group_names.control_plane })
  vpc_id      = local.vpc_id
}
