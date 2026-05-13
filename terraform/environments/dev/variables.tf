variable "tenancy_ocid" {
  description = "The OCID of the tenancy."
  type        = string
}

variable "user_ocid" {
  description = "The OCID of the user."
  type        = string
}

variable "fingerprint" {
  description = "The fingerprint for the API key."
  type        = string
}

variable "private_key_path" {
  description = "The path to the private key for the API."
  type        = string
}

variable "ssh_private_key_path" {
  description = "The path to the SSH private key used to access the compute instance."
  type        = string
}

variable "ssh_public_key" {
  description = "The content of the SSH public key."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "The OCI region."
  type        = string
}

variable "compartment_ocid" {
  description = "The OCID of the compartment to create resources in."
  type        = string
}

variable "project_prefix" {
  description = "A prefix for all resource names."
  type        = string
  default     = "saas-platform"
}

variable "tags" {
  description = "A map of tags to apply to all resources."
  type        = map(string)
  default = {
    "ManagedBy" = "Terraform"
    "Project"   = "SaaS-Platform"
  }
}

variable "ssh_source_cidr" {
  description = "The source IP address for SSH access. For security, set this to your own IP address (e.g., '1.2.3.4/32')."
  type        = string
  default     = "0.0.0.0/0"
}

variable "instance_shape" {
  description = "The shape of the VM. This is set by the retry script."
  default     = "VM.Standard.E2.1.Micro"
}

variable "instance_ocpus" {
  description = "The number of OCPUs for the VM. This is set by the retry script."
  default     = 1 # For Micro shape, this is fixed.
}

variable "instance_memory_in_gbs" {
  description = "The amount of memory in GBs for the VM. This is set by the retry script."
  default     = 1 # For Micro shape, this is fixed.
}

variable "availability_domain_index" {
  description = "The index of the availability domain to use (0, 1, or 2). Set by the retry script."
  type        = number
  default     = 0 # A sensible default for manual runs
}

variable "api_domain" {
  description = "The domain name for the API endpoint (e.g., api.yourdomain.com)."
  type        = string
}

variable "repo_url" {
  description = "The URL of the git repository to clone into the VMs."
  type        = string
  default     = "https://github.com/Alzis/oci-saas-platform-v3.git"
}

variable "api_instance_count" {
  description = "The number of VM instances to create for the API."
  type        = number
  default     = 1
}

variable "create_observability_vm" {
  description = "Set to true to create a dedicated VM for the observability stack."
  type        = bool
  default     = true
}