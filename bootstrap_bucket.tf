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

# Holds the bootstrap payloads machines and pools stage for their instances
# (DESIGN.md "Bootstrap payloads are staged in S3"). bucket_prefix: bucket
# names are global across every AWS account, so the name is generated.
resource "aws_s3_bucket" "bootstrap_bucket" {
  # count = 1, not a bare resource: once a refresh drops a bare resource
  # from state its references read as unknown, which try() cannot catch, so
  # the outputs would go null; an empty tuple fails the index, and try()
  # falls back (checked on Terraform 1.16.4 and OpenTofu 1.12.6).
  count = 1

  bucket_prefix = "captf-bootstrap-"
  # The cluster is destroyed only after every machine and pool is gone
  # (cluster.md "Delete ordering"), so any object left is an orphan.
  force_destroy = true
  tags          = local.tags
}
