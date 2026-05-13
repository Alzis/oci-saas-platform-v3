variable "compartment_id" {
  description = "The OCID of the compartment where resources will be created."
  type        = string
}

variable "tenancy_ocid" {
  description = "The OCID of the tenancy (root compartment) for fetching platform images."
  type        = string
}

variable "availability_domain" {
  description = "The availability domain to create the instance in."
  type        = string
}

variable "instance_shape" {
  description = "The shape for the compute instance."
  type        = string
}

variable "project_prefix" {
  description = "A prefix to apply to the instance display name."
  type        = string
}

variable "subnet_id" {
  description = "The OCID of the subnet to create the VNIC in."
  type        = string
}

variable "nsg_id" {
  description = "The OCID of the Network Security Group to associate with the VNIC."
  type        = string
}

variable "ssh_public_key" {
  description = "The SSH public key to use for the compute instance."
  type        = string
  sensitive   = true
}

variable "user_data_base64" {
  description = "The base64 encoded cloud-init script."
  type        = string
}

variable "tags" {
  description = "A map of tags to apply to all resources."
  type        = map(string)
  default     = {}
}

variable "instance_ocpus" {
  description = "The number of OCPUs for a flexible shape instance."
  type        = number
  default     = null
}

variable "instance_memory_in_gbs" {
  description = "The amount of memory in GBs for a flexible shape instance."
  type        = number
  default     = null
}