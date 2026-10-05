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

# The exports output, injected into machines and pools as
# captf_cluster_outputs (CONVENTIONS.md section 12). Nothing here is secret:
# exports are stored in clear and copied into every machine's inputs. Adding
# a key keeps the schema; renaming or removing one bumps it to
# captf.io/aws-cluster/v2. Resource attributes are try()-guarded: a
# resource deleted out of band leaves state on refresh, and the output must
# still evaluate so health can report it.
locals {
  exports = {
    schema                = "captf.io/aws-cluster/v1"
    region                = data.aws_region.current_region.region
    vpc_id                = local.vpc_id
    kubernetes_cluster_id = local.kubernetes_cluster_id
    failure_domains       = { for z, d in local.failure_domains : z => { subnet_id = d.subnet_id } }
    # Control-plane nodes carry both groups; the node group is the one the
    # cloud controller manager manages rules on.
    security_group_ids = {
      control_plane = [try(aws_security_group.control_plane_security_group[0].id, null), try(aws_security_group.node_security_group[0].id, null)]
      worker        = [try(aws_security_group.node_security_group[0].id, null)]
    }
    instance_profiles = local.node_instance_profile_names
    # Control-plane machines register in every target group (machine.md
    # "Control-plane machines"). Null with a user endpoint: nothing to
    # register in.
    api = local.api_load_balancer_enabled ? {
      host = try(aws_lb.api_load_balancer[0].dns_name, null)
      port = local.api_server_port
      # Each target group's port is the backend port the machine registers.
      target_groups = {
        for k, p in local.api_load_balancer_ports : k => {
          arn  = try(aws_lb_target_group.api_target_groups[k].arn, null)
          port = p.backend_port
        }
      }
    } : null
    bootstrap_bucket = try(aws_s3_bucket.bootstrap_bucket[0].bucket, null)
  }
}
