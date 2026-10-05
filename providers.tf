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

# The AWS provider. Only the region is set here: credentials come from the
# identity Secret through the SDK's default chain (environment variables, or
# AWS_CONFIG_FILE and AWS_SHARED_CREDENTIALS_FILE under
# /var/run/captf/credentials), never from module source (README "Identity
# Secret"). A null region falls back to AWS_REGION.
provider "aws" {
  region = var.region
}
