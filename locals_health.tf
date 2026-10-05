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

# Cluster health ("health" in
# https://captf.io/docs/module-author/contract/v1alpha1/common.html,
# CONVENTIONS.md section 10). It comes from the cluster's own resources,
# never from load balancer targets: cluster health feeds Ready, and targets
# are unhealthy during every normal control-plane bring-up. A refresh drops
# a resource deleted out of band from state, so presence is the signal.
# The API load balancer is the primary resource: gone, the cluster is
# terminated. The bootstrap bucket gone leaves it degraded: running nodes
# keep working, new machines cannot boot.
locals {
  # Both are counted resources: a vanished one reads as an empty tuple, and
  # the length is known at plan time too.
  api_load_balancer_present = !local.api_load_balancer_enabled || length(aws_lb.api_load_balancer) > 0
  bootstrap_bucket_present  = length(aws_s3_bucket.bootstrap_bucket) > 0

  health_reading = (
    !local.api_load_balancer_present ? {
      state   = "terminated"
      healthy = false
      message = "API load balancer ${local.api_load_balancer_name} not found"
      reasons = ["LoadBalancerNotFound"]
    } :
    !local.bootstrap_bucket_present ? {
      state   = "degraded"
      healthy = false
      message = "bootstrap bucket not found"
      reasons = ["BootstrapBucketNotFound"]
    } :
    {
      state   = "running"
      healthy = true
      message = local.api_load_balancer_enabled ? "API load balancer ${local.api_load_balancer_name} and bootstrap bucket present" : "bootstrap bucket present; the API endpoint is user-supplied"
      reasons = []
    }
  )
}
