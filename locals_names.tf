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

# Cloud resource names, derived from the cluster's key with a hash that keeps
# truncated names unique (CONVENTIONS.md section 6). Nothing here may change
# for the life of a cluster: every name below is ForceNew on its resource.
locals {
  cluster_key  = "${var.captf_cluster.namespace}/${var.captf_cluster.name}"
  cluster_hash = substr(sha256(local.cluster_key), 0, 8)
  # Kubernetes names may hold dots; AWS load balancer and target group names
  # may not, so every character outside [a-z0-9-] becomes "-".
  name_base = replace(lower("captf-${var.captf_cluster.namespace}-${var.captf_cluster.name}"), "/[^a-z0-9-]/", "-")

  # At most 40 characters: 40 - 9 leaves room for "-" and the hash, and the
  # longest suffix added below ("-control-plane") keeps IAM role names within
  # their 64-character limit.
  name_prefix = "${trimsuffix(substr(local.name_base, 0, 40 - 9), "-")}-${local.cluster_hash}"

  # Load balancer and target group names hold at most 32 characters
  # (https://docs.aws.amazon.com/elasticloadbalancing/latest/APIReference/API_CreateLoadBalancer.html).
  # Target groups add a 5-character suffix per port ("-kapi", "-rke2").
  api_load_balancer_name   = "${trimsuffix(substr(local.name_base, 0, 32 - 9), "-")}-${local.cluster_hash}"
  target_group_name_prefix = "${trimsuffix(substr(local.name_base, 0, 32 - 9 - 5), "-")}-${local.cluster_hash}"

  security_group_names = {
    api_load_balancer = "${local.name_prefix}-api-lb"
    control_plane     = "${local.name_prefix}-control-plane"
    node              = "${local.name_prefix}-node"
  }

  # The cluster ID of cloud-provider-aws: it finds its cluster through the
  # kubernetes.io/cluster/<id> tag on its own instance and tags what it
  # creates with it. Exported so machines and pools tag their instances.
  kubernetes_cluster_id = local.name_prefix
}
