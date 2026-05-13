variable "compartment_id" {
  description = "The OCID of the compartment to create resources in."
  type        = string
}

variable "project_prefix" {
  description = "A prefix to apply to all created resources."
  type        = string
}

variable "vcn_cidr" {
  description = "The CIDR block for the VCN."
  type        = string
}

variable "subnet_cidr" {
  description = "The CIDR block for the public subnet."
  type        = string
}

variable "tags" {
  description = "A map of tags to apply to all resources."
  type        = map(string)
  default     = {}
}

variable "ssh_source_cidr" {
  description = "The source CIDR block for SSH access."
  type        = string
  default     = "0.0.0.0/0" # Default to open, but should be overridden
}