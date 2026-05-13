terraform {
  required_providers {
    oci = {
      source = "oracle/oci",
      version = ">= 5.0"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
  user_ocid        = var.user_ocid
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

module "network" {
  source         = "../../modules/network"
  compartment_id = var.compartment_ocid
  project_prefix = var.project_prefix
  vcn_cidr       = "10.0.0.0/16"
  subnet_cidr    = "10.0.1.0/24"
  tags           = var.tags
}

module "compute" {
  source              = "../../modules/compute"
  compartment_id      = var.compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  instance_shape      = "VM.Standard.E2.1.Micro"
  project_prefix      = var.project_prefix
  ssh_public_key      = var.ssh_public_key
  subnet_id           = module.network.public_subnet_id
  nsg_id              = module.network.app_nsg_id
  user_data_base64    = base64encode(file("../../../scripts/cloud-init.sh"))
  tags                = var.tags
}

data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.compartment_ocid
}

resource "oci_objectstorage_bucket" "frontend_bucket" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = "${var.project_prefix}-frontend-bucket"
  access_type    = "ObjectReadWithoutList"
  tags           = var.tags
  
  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_objectstorage_object" "frontend_index" {
  bucket         = oci_objectstorage_bucket.frontend_bucket.name
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  object         = "index.html"
  content_type   = "text/html"
  content        = templatefile("../../../frontend/index.html", { api_endpoint = module.compute.public_ip })
  depends_on     = [module.compute]
}

output "instance_public_ip" {
  description = "Public IP address of the application VM."
  value       = module.compute.public_ip
}

output "frontend_url" {
  description = "URL for the frontend hosted in OCI Object Storage."
  value       = "https://objectstorage.${var.region}.oraclecloud.com/n/${data.oci_objectstorage_namespace.ns.namespace}/b/${oci_objectstorage_bucket.frontend_bucket.name}/o/index.html"
}

output "ssh_command" {
  description = "SSH command to connect to the VM."
  value       = "ssh -i ${var.ssh_private_key_path} ubuntu@${module.compute.public_ip}"
  sensitive   = true
}
