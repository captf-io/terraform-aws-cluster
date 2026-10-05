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

# One target group per API port, on the backend port (always 6443 for the
# kube-apiserver of RKE2). Control-plane machines register themselves in
# their own state (machine.md "Control-plane machines").
#
# preserve_client_ip is off: "NAT loopback, also known as hairpinning, is not
# supported when client IP preservation is enabled"
# (https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-troubleshooting.html),
# and a control-plane node must reach the endpoint it is registered behind.
# TCP health checks go green with a single backend during kubeadm init and
# tolerate an RKE2 supervisor that is not up yet (control-plane checklist).
resource "aws_lb_target_group" "api_target_groups" {
  for_each = local.api_load_balancer_ports

  # Shorter than the 300 s default: a removed control-plane node stops
  # receiving connections quickly during a rollout.
  deregistration_delay = "30"
  name                 = "${local.target_group_name_prefix}-${each.value.name_suffix}"
  port                 = each.value.backend_port
  preserve_client_ip   = "false"
  protocol             = "TCP"
  tags                 = local.tags
  target_type          = "instance"
  vpc_id               = local.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 10
    port                = "traffic-port"
    protocol            = "TCP"
    unhealthy_threshold = 2
  }
}
