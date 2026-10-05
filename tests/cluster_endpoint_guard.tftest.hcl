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

# The endpoint guard across applies: a cluster is created, then each run
# changes one input that would replace the load balancer or move the
# endpoint, and the postcondition on terraform_data.api_endpoint_guard must
# stop it.
# Adding a subnet is allowed: it updates the load balancer in place.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }
  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }
  mock_data "aws_vpc" {
    defaults = {
      cidr_block = "10.0.0.0/16"
    }
  }
  # vpc_id names one VPC.
  mock_data "aws_vpcs" {
    defaults = {
      ids = ["vpc-0123456789abcdef0"]
    }
  }
  mock_data "aws_subnets" {
    defaults = {
      ids = ["subnet-0aaa0000000000001"]
    }
  }
  mock_resource "aws_lb" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/captf-team-a-demo-1960e37c/0123456789abcdef"
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/captf-team-a-demo-1960e37c-kapi/0123456789abcdef"
    }
  }
}

variables {
  captf_contract            = "v1alpha1"
  captf_cluster             = { name = "demo", namespace = "team-a" }
  captf_object              = { kind = "TerraformCluster", name = "demo", namespace = "team-a" }
  captf_tags                = { "captf.io/cluster" = "demo", "captf.io/namespace" = "team-a", "captf.io/kind" = "TerraformCluster", "captf.io/name" = "demo", "captf.io/managed-by" = "captf", "captf.io/template" = "" }
  control_plane_endpoint    = null
  kubernetes_version        = null
  control_plane_initialized = false
  cluster_network           = { pods = [], services = [], service_domain = null, api_server_port = 7443 }
  vpc_id                    = "vpc-0123456789abcdef0"
  subnets                   = { "us-east-1a" = "subnet-0aaa0000000000001", "us-east-1b" = "subnet-0bbb0000000000002" }
}

run "create" {
  assert {
    condition     = output.control_plane_endpoint == { host = aws_lb.api_load_balancer[0].dns_name, port = 7443 }
    error_message = "the endpoint port must follow cluster_network.api_server_port."
  }
}

run "rejects_api_load_balancer_public_change" {
  command = plan

  variables {
    api_load_balancer_public  = true
    api_allowed_cidrs         = ["198.51.100.0/24"]
    api_load_balancer_subnets = { "us-east-1a" = "subnet-0aaa0000000000001", "us-east-1b" = "subnet-0bbb0000000000002" }
  }

  expect_failures = [terraform_data.api_endpoint_guard]
}

run "rejects_api_server_port_change" {
  command = plan

  variables {
    cluster_network = { pods = [], services = [], service_domain = null, api_server_port = 6443 }
  }

  expect_failures = [terraform_data.api_endpoint_guard]
}

run "rejects_api_load_balancer_subnets_change" {
  command = plan

  variables {
    subnets = { "us-east-1a" = "subnet-0aaa0000000000001" }
  }

  expect_failures = [terraform_data.api_endpoint_guard]
}

run "adding_a_subnet_keeps_the_endpoint" {
  # created_endpoint is test-only: OpenTofu does not resolve run.<name>
  # inside an assert.
  variables {
    subnets          = { "us-east-1a" = "subnet-0aaa0000000000001", "us-east-1b" = "subnet-0bbb0000000000002", "us-east-1c" = "subnet-0ccc0000000000003" }
    created_endpoint = run.create.control_plane_endpoint
  }

  assert {
    condition     = jsonencode(output.control_plane_endpoint) == jsonencode(var.created_endpoint)
    error_message = "adding a subnet must update the load balancer in place and keep the endpoint."
  }
  assert {
    condition     = length(aws_lb.api_load_balancer[0].subnets) == 3
    error_message = "the load balancer must span the added subnet."
  }
}

# Documented behaviour, not a feature: the guard records the subnets of the
# creation only, so removing a subnet added later passes it, and the plan
# would replace the load balancer. CAPTF's destructive-plan guard is the
# backstop (README "Limitations").
run "removing_a_later_subnet_passes_the_guard" {
  command = plan

  assert {
    condition     = length(aws_lb.api_load_balancer[0].subnets) == 2
    error_message = "the guard does not see subnets added after creation."
  }
}
