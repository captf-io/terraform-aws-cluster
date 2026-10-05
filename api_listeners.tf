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

# One TCP listener per API port, each forwarding to its target group: the
# endpoint port is cluster_network.api_server_port, and the RKE2 join URL's
# 9345 resolves on the endpoint host.
resource "aws_lb_listener" "api_listeners" {
  for_each = local.api_load_balancer_ports

  load_balancer_arn = aws_lb.api_load_balancer[0].arn
  port              = each.value.listener_port
  protocol          = "TCP"
  tags              = local.tags

  default_action {
    target_group_arn = aws_lb_target_group.api_target_groups[each.key].arn
    type             = "forward"
  }
}
