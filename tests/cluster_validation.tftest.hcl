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

# One expect_failures run per variable validation of the cluster role
# (CONVENTIONS.md section 14), each against an otherwise valid cluster.

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
  cluster_network           = null
  vpc_id                    = "vpc-0123456789abcdef0"
  subnets                   = { "us-east-1a" = "subnet-0aaa0000000000001" }
}

run "valid_baseline" {
  command = plan

  assert {
    condition     = length(aws_lb.api_load_balancer) == 1
    error_message = "the baseline every other run varies must plan."
  }
}

run "invalid_captf_contract" {
  command = plan

  variables {
    captf_contract = "v1alpha2"
  }

  expect_failures = [var.captf_contract]
}

run "invalid_additional_tags_count" {
  command = plan

  variables {
    additional_tags = { for i in range(41) : "tag-${i}" => "x" }
  }

  expect_failures = [var.additional_tags]
}

run "invalid_additional_tags_length" {
  command = plan

  variables {
    additional_tags = { team = join("", [for i in range(257) : "x"]) }
  }

  expect_failures = [var.additional_tags]
}

run "invalid_additional_tags_reserved" {
  command = plan

  variables {
    additional_tags = { "captf.io/cluster" = "other" }
  }

  expect_failures = [var.additional_tags]
}

run "invalid_additional_tags_charset" {
  command = plan

  variables {
    additional_tags = { team = "a,b" }
  }

  expect_failures = [var.additional_tags]
}

run "invalid_api_allowed_cidrs" {
  command = plan

  variables {
    api_allowed_cidrs = ["192.0.2.1/24"]
  }

  expect_failures = [var.api_allowed_cidrs]
}

run "invalid_api_load_balancer_subnets" {
  command = plan

  variables {
    api_load_balancer_subnets = { "us-east-1a" = "sn-123" }
  }

  expect_failures = [var.api_load_balancer_subnets]
}

run "invalid_control_plane_instance_profile" {
  command = plan

  variables {
    control_plane_instance_profile = { name = "platform-cp", role_arn = "platform-cp" }
  }

  expect_failures = [var.control_plane_instance_profile]
}

run "invalid_worker_instance_profile" {
  command = plan

  variables {
    worker_instance_profile = { name = "", role_arn = "arn:aws:iam::123456789012:role/worker" }
  }

  expect_failures = [var.worker_instance_profile]
}

run "rejects_shared_node_role" {
  command = plan

  variables {
    control_plane_instance_profile = { name = "platform-node", role_arn = "arn:aws:iam::123456789012:role/node" }
    worker_instance_profile        = { name = "platform-node", role_arn = "arn:aws:iam::123456789012:role/node" }
  }

  expect_failures = [aws_s3_bucket_policy.bootstrap_bucket_policy]
}

run "invalid_ssh_allowed_cidrs" {
  command = plan

  variables {
    ssh_allowed_cidrs = ["0.0.0.0"]
  }

  expect_failures = [var.ssh_allowed_cidrs]
}

run "invalid_distribution" {
  command = plan

  variables {
    distribution = "k3s"
  }

  expect_failures = [var.distribution]
}

run "invalid_node_role_permissions_boundary" {
  command = plan

  variables {
    node_role_permissions_boundary = "boundary"
  }

  expect_failures = [var.node_role_permissions_boundary]
}

run "invalid_node_role_policy_arns" {
  command = plan

  variables {
    node_role_policy_arns = { worker = ["AmazonSSMManagedInstanceCore"] }
  }

  expect_failures = [var.node_role_policy_arns]
}

run "invalid_region" {
  command = plan

  variables {
    region = "US East"
  }

  expect_failures = [var.region]
}

run "invalid_subnets_required" {
  command = plan

  variables {
    subnets = null
  }

  expect_failures = [var.subnets]
}

run "invalid_subnets_format" {
  command = plan

  variables {
    subnets = { "us-east-1a" = "vpc-0123456789abcdef0" }
  }

  expect_failures = [var.subnets]
}

run "invalid_subnets_repeated" {
  command = plan

  variables {
    subnets = { "us-east-1a" = "subnet-0aaa0000000000001", "us-east-1b" = "subnet-0aaa0000000000001" }
  }

  expect_failures = [var.subnets]
}

run "invalid_vpc_id_required" {
  command = plan

  variables {
    vpc_id = null
  }

  expect_failures = [var.vpc_id]
}

run "invalid_vpc_id_format" {
  command = plan

  variables {
    vpc_id = "subnet-0aaa0000000000001"
  }

  expect_failures = [var.vpc_id]
}
