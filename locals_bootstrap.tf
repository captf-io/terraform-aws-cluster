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

# The bootstrap bucket's policy. Machines and pools stage each bootstrap
# payload as an object here and boot from a small stub that fetches it
# (DESIGN.md "Bootstrap payloads are staged in S3"). Access is by key prefix:
# control-plane nodes read control-plane/*, workers read worker/* and pool/*,
# so a worker can never read a control-plane payload and the cluster CA keys
# in it. The allows alone would not ensure that: within an account, a
# worker role with s3:GetObject on * in its own policies could read any
# prefix, so an explicit Deny keeps workers out of control-plane/*. Other
# principals of the account with broad S3 read can still read it.
locals {
  bootstrap_key_prefixes = {
    control_plane = ["control-plane/"]
    worker        = ["worker/", "pool/"]
  }

  bootstrap_bucket_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.bootstrap_bucket[0].arn,
          "${aws_s3_bucket.bootstrap_bucket[0].arn}/*",
        ]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }],
      [
        for role, prefixes in local.bootstrap_key_prefixes : {
          Sid       = role == "control_plane" ? "ControlPlaneNodesReadPayloads" : "WorkerNodesReadPayloads"
          Effect    = "Allow"
          Principal = { AWS = local.node_role_arns[role] }
          Action    = "s3:GetObject"
          Resource  = [for p in prefixes : "${aws_s3_bucket.bootstrap_bucket[0].arn}/${p}*"]
        }
      ],
      [{
        Sid       = "DenyWorkerNodesControlPlanePayloads"
        Effect    = "Deny"
        Principal = { AWS = local.node_role_arns.worker }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.bootstrap_bucket[0].arn}/control-plane/*"
      }],
    )
  })
}
