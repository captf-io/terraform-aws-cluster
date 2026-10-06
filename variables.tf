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

# User variables of the cluster role, alphabetical. Set them through
# TerraformCluster spec.variables or spec.variablesFrom
# (https://captf.io/docs/user-guide/variables.html).

variable "additional_tags" {
  description = "Extra tags for every taggable resource. The captf tags are merged last and win, so these cannot override them."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    # 50 tags per AWS resource, less the captf tags (6) and the module's own
    # (Name, kubernetes.io/cluster/<id>), with headroom.
    condition     = length(var.additional_tags) <= 40
    error_message = "additional_tags holds at most 40 tags: AWS allows 50 per resource and the module sets up to 8 itself."
  }
  validation {
    condition = alltrue([
      for k, v in var.additional_tags :
      length(k) >= 1 && length(k) <= 128 && length(v) <= 256
    ])
    error_message = "additional_tags must have keys of 1 to 128 characters and values of at most 256 characters, the AWS tag limits."
  }
  validation {
    # The tag character set IAM, Elastic Load Balancing and Auto Scaling
    # enforce, the strictest of the services tagged here.
    condition     = alltrue([for k, v in var.additional_tags : can(regex("^[\\p{L}\\p{Z}\\p{N}_.:/=+\\-@]*$", k)) && can(regex("^[\\p{L}\\p{Z}\\p{N}_.:/=+\\-@]*$", v))])
    error_message = "additional_tags must use only letters, numbers, spaces and _ . : / = + - @ in keys and values, the AWS tag character set."
  }
  validation {
    condition = alltrue([
      for k in keys(var.additional_tags) :
      !startswith(lower(k), "aws:") && !startswith(k, "captf.io/") && !startswith(k, "kubernetes.io/cluster/")
    ])
    error_message = "additional_tags must not use the aws: prefix (reserved by AWS), captf.io/ (the captf tags) or kubernetes.io/cluster/ (the cluster ownership tag)."
  }
}

variable "api_allowed_cidrs" {
  description = "IPv4 CIDRs allowed to reach the API endpoint, besides the nodes. Empty means the VPC's primary CIDR for an internal load balancer. An internet-facing one requires an explicit list, which must include the nodes' public egress addresses (the NAT gateways' Elastic IPs as /32s): its DNS name resolves to public addresses, so node traffic arrives from those."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for c in var.api_allowed_cidrs : try(can(cidrnetmask(c)) && cidrsubnet(c, 0, 0) == c, false)])
    error_message = "api_allowed_cidrs must hold IPv4 network addresses in CIDR notation, such as 192.0.2.0/24 (not a host address such as 192.0.2.1/24)."
  }

  validation {
    condition     = alltrue([for c in var.api_allowed_cidrs : try(tonumber(split("/", c)[1]) > 0, true)])
    error_message = "api_allowed_cidrs must not hold a /0 prefix such as 0.0.0.0/0: it would open the API endpoint to the whole internet. List the networks that need access and the nodes' public egress addresses instead, or leave the list empty to keep an internal load balancer to the VPC's primary CIDR."
  }
}

variable "api_load_balancer_public" {
  description = "Make the API load balancer internet-facing. False keeps it internal: the API is then reachable only from the VPC and the networks routed to it."
  type        = bool
  default     = false
  nullable    = false
}

variable "api_load_balancer_subnets" {
  description = "Subnets for the API load balancer as a map of availability zone to subnet ID, for example public subnets for an internet-facing one; it must cover every zone of subnets, since a Network Load Balancer sends no traffic to targets in a zone it has no subnet in. Empty means the node subnets. Zones can be added later, not removed."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for z, s in var.api_load_balancer_subnets : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+[a-z]+(-[a-z0-9]+)?$", z)) && startswith(s, "subnet-")])
    error_message = "api_load_balancer_subnets must map availability zone names (such as us-east-1a) to subnet IDs (subnet-...)."
  }
}

variable "control_plane_instance_profile" {
  description = "An existing instance profile for control-plane nodes, with its role's ARN, to use instead of creating one. The role ARN is given, not read, so a profile deleted before the cluster cannot block its destroy. Null creates an IAM role and instance profile."
  type = object({
    name     = string
    role_arn = string
  })
  default = null

  validation {
    condition     = var.control_plane_instance_profile == null || try(length(var.control_plane_instance_profile.name) > 0 && can(regex("^arn:[a-z-]+:iam::[0-9]{12}:role/", var.control_plane_instance_profile.role_arn)), false)
    error_message = "control_plane_instance_profile must give an instance profile name and its role's ARN (arn:<partition>:iam::<account>:role/...), or be null."
  }
}

variable "distribution" {
  description = "The control-plane distribution: kubeadm (KubeadmControlPlane) or rke2 (RKE2ControlPlane). rke2 adds the supervisor listener on 9345 and its security group rules."
  type        = string
  default     = "kubeadm"
  nullable    = false

  validation {
    condition     = contains(["kubeadm", "rke2"], var.distribution)
    error_message = "distribution must be kubeadm or rke2."
  }
}

variable "node_role_permissions_boundary" {
  description = "ARN of a permissions boundary for the node IAM roles the module creates, for accounts that require one. Null sets none. The boundary limits the bucket policy's grant too, so it must allow s3:GetObject on the bootstrap bucket (captf-bootstrap-*), besides the cloud-provider-aws and ECR actions of locals_iam.tf."
  type        = string
  default     = null

  validation {
    condition     = var.node_role_permissions_boundary == null || can(regex("^arn:[a-z-]+:iam::[0-9]{12}:policy/", var.node_role_permissions_boundary))
    error_message = "node_role_permissions_boundary must be an IAM policy ARN (arn:<partition>:iam::<account>:policy/...) or null."
  }
}

variable "node_role_policy_arns" {
  description = "Managed policies to attach to the node IAM roles the module creates (not to brought instance profiles), for example AmazonEBSCSIDriverPolicy or AmazonSSMManagedInstanceCore. None by default: least privilege."
  type = object({
    control_plane = optional(list(string), [])
    worker        = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for a in concat(var.node_role_policy_arns.control_plane, var.node_role_policy_arns.worker) : can(regex("^arn:[a-z-]+:iam::([0-9]{12}|aws):policy/", a))])
    error_message = "node_role_policy_arns must hold IAM policy ARNs (arn:<partition>:iam::<account or aws>:policy/...)."
  }
}

variable "region" {
  description = "AWS region of the cluster. Null uses AWS_REGION from the identity Secret. Machines and pools inherit it through exports."
  type        = string
  default     = null

  validation {
    condition     = var.region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.region))
    error_message = "region must be an AWS region name such as us-east-1, or null."
  }
}

variable "ssh_allowed_cidrs" {
  description = "IPv4 CIDRs allowed to reach the nodes on SSH (22). Empty, the default, admits none; machines and pools also need ssh_key_name or another way in."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for c in var.ssh_allowed_cidrs : try(can(cidrnetmask(c)) && cidrsubnet(c, 0, 0) == c, false)])
    error_message = "ssh_allowed_cidrs must hold IPv4 network addresses in CIDR notation, such as 192.0.2.0/24."
  }
}

variable "subnets" {
  description = "Required. The node subnets, one per availability zone, as a map of zone name to subnet ID; each zone becomes a failure domain. Set spec.variables.subnets on the TerraformCluster, for example {\"us-east-1a\": \"subnet-0a1...\"}."
  type        = map(string)
  default     = null

  validation {
    condition     = var.subnets != null
    error_message = "subnets is required: set spec.variables.subnets on the TerraformCluster to a map of availability zone to node subnet ID, one subnet per zone."
  }
  validation {
    condition     = try(length(var.subnets) > 0 && alltrue([for z, s in var.subnets : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+[a-z]+(-[a-z0-9]+)?$", z)) && startswith(s, "subnet-")]), var.subnets == null)
    error_message = "subnets must map at least one availability zone name (such as us-east-1a) to a subnet ID (subnet-...)."
  }
  validation {
    condition     = try(length(distinct(values(var.subnets))) == length(var.subnets), var.subnets == null)
    error_message = "subnets must not name one subnet for two zones: a subnet lives in exactly one availability zone."
  }
}

variable "vpc_id" {
  description = "Required. The VPC the node subnets belong to; security groups and target groups are created in it. Set spec.variables.vpc_id on the TerraformCluster."
  type        = string
  default     = null

  validation {
    condition     = var.vpc_id != null
    error_message = "vpc_id is required: set spec.variables.vpc_id on the TerraformCluster to the VPC of the node subnets."
  }
  validation {
    condition     = var.vpc_id == null || startswith(coalesce(var.vpc_id, "-"), "vpc-")
    error_message = "vpc_id must be a VPC ID (vpc-...)."
  }
}

variable "worker_instance_profile" {
  description = "An existing instance profile for worker nodes, with its role's ARN, to use instead of creating one. The role ARN is given, not read, so a profile deleted before the cluster cannot block its destroy. Null creates an IAM role and instance profile."
  type = object({
    name     = string
    role_arn = string
  })
  default = null

  validation {
    condition     = var.worker_instance_profile == null || try(length(var.worker_instance_profile.name) > 0 && can(regex("^arn:[a-z-]+:iam::[0-9]{12}:role/", var.worker_instance_profile.role_arn)), false)
    error_message = "worker_instance_profile must give an instance profile name and its role's ARN (arn:<partition>:iam::<account>:role/...), or be null."
  }
}
