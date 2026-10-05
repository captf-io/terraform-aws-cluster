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

# TLS only, and read access by key prefix for each node role
# (locals_bootstrap.tf).
resource "aws_s3_bucket_policy" "bootstrap_bucket_policy" {
  bucket = aws_s3_bucket.bootstrap_bucket[0].id
  policy = local.bootstrap_bucket_policy

  # S3 rejects concurrent configuration changes to one bucket
  # (OperationAborted, hashicorp/terraform-provider-aws#7628), and nothing in
  # the policy references the public access block, so the graph alone would
  # run the two in parallel.
  lifecycle {
    precondition {
      # Created roles always differ; only two brought ones can coincide.
      condition     = try(var.control_plane_instance_profile.role_arn != var.worker_instance_profile.role_arn, true)
      error_message = "control_plane_instance_profile and worker_instance_profile must use different roles: the bucket policy denies the worker role the control-plane payloads, which hold the cluster CA keys."
    }
  }

  depends_on = [aws_s3_bucket_public_access_block.bootstrap_bucket_public_access]
}
