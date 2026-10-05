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

# Contract inputs of the cluster role, in contract order, with the contract's
# types: https://captf.io/docs/module-author/contract/v1alpha1/common.html
# and https://captf.io/docs/module-author/contract/v1alpha1/cluster.html

# Only its validation reads it: the module asserts the contract version.
# tflint-ignore: terraform_unused_declarations
variable "captf_contract" {
  description = "Contract version the controller generated the root for; always v1alpha1."
  type        = string

  validation {
    condition     = var.captf_contract == "v1alpha1"
    error_message = "captf_contract must be v1alpha1: this module implements the v1alpha1 cluster role."
  }
}

variable "captf_cluster" {
  description = "The owning CAPI Cluster: name and namespace."
  type = object({
    name      = string
    namespace = string
  })
}

# tflint-ignore: terraform_unused_declarations
variable "captf_object" {
  description = "The TerraformCluster being reconciled: kind, name and namespace."
  type = object({
    kind      = string
    name      = string
    namespace = string
  })
}

# The controller never passes this to the cluster role; the declaration with
# default = null keeps validate passing (cluster.md "Inputs").
# tflint-ignore: terraform_unused_declarations
variable "captf_cluster_outputs" {
  description = "Not passed to the cluster role; declared with a null default as the contract allows."
  type        = any
  default     = null
}

variable "captf_tags" {
  description = "Tags the controller always sets (captf.io/cluster, captf.io/namespace, captf.io/kind, captf.io/name, captf.io/managed-by, captf.io/template); applied to every taggable resource."
  type        = map(string)
}

variable "control_plane_endpoint" {
  description = "An endpoint the module does not own (set by the user or a control-plane provider). Non-null skips the API load balancer and is passed through."
  type = object({
    host = string
    port = number
  })
  default = null
}

# tflint-ignore: terraform_unused_declarations
variable "kubernetes_version" {
  description = "Cluster.spec.topology.version, null without ClusterClass. Unused: nothing the cluster role creates depends on the Kubernetes version."
  type        = string
  default     = null
}

# tflint-ignore: terraform_unused_declarations
variable "control_plane_initialized" {
  description = "Cluster.status.initialization.controlPlaneInitialized, latched. Unused: the cluster role creates nothing that needs a live workload API server."
  type        = bool
}

variable "cluster_network" {
  description = "Cluster.spec.clusterNetwork. api_server_port sets the API port (default 6443); pods opens the API port to pod CIDRs."
  type = object({
    pods            = list(string)
    services        = list(string)
    service_domain  = string
    api_server_port = number
  })
  default = null
}
