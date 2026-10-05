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

# Non-contract outputs, alphabetical. The controller never reads them; they
# name the cloud objects behind the cluster for operators.

output "api_load_balancer_id" {
  description = "The API Network Load Balancer's ARN; null with a user-supplied endpoint or once the load balancer is gone."
  value       = try(aws_lb.api_load_balancer[0].arn, null)
}
