terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "5.30.0" # Pin to a specific recent version to force a clean download
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1"
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

# --- Dados e Namespaces ---
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.compartment_ocid
}

# --- Módulos de Infraestrutura ---
module "network" {
  source          = "../../modules/network"
  compartment_id  = var.compartment_ocid
  project_prefix  = var.project_prefix
  vcn_cidr        = "10.0.0.0/16"
  subnet_cidr     = "10.0.1.0/24"
  tags            = var.tags
  ssh_source_cidr = var.ssh_source_cidr
}

module "compute_api" {
  count               = var.api_instance_count
  source              = "../../modules/compute"
  tenancy_ocid        = var.tenancy_ocid # Adicionado para a busca de imagens
  compartment_id      = var.compartment_ocid
  # Tenta o AD especificado e distribui as instâncias seguintes pelos outros ADs.
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[(var.availability_domain_index + count.index) % length(data.oci_identity_availability_domains.ads.availability_domains)].name
  instance_shape      = var.instance_shape
  project_prefix      = "${var.project_prefix}-api-${count.index + 1}" # Nomeia as VMs como saas-platform-api-1
  ssh_public_key      = var.ssh_public_key
  subnet_id           = module.network.public_subnet_id
  nsg_id              = module.network.app_nsg_id
  user_data_base64    = base64encode(templatefile("../../../scripts/cloud-init.sh", {
    compose_file = "docker-compose.yml", # This is the API compose file
    REPO_URL     = var.repo_url
  }))
  tags                = var.tags
  instance_ocpus      = var.instance_ocpus
  instance_memory_in_gbs = var.instance_memory_in_gbs
}

module "compute_obs" {
  count               = var.create_observability_vm ? 1 : 0
  source              = "../../modules/compute"
  tenancy_ocid        = var.tenancy_ocid
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.availability_domain_index].name
  instance_shape      = var.instance_shape # Considere usar um shape diferente se necessário
  project_prefix      = "${var.project_prefix}-obs"
  ssh_public_key      = var.ssh_public_key
  subnet_id           = module.network.public_subnet_id
  nsg_id              = module.network.obs_nsg_id # Novo NSG para observabilidade
  user_data_base64    = base64encode(templatefile("../../../scripts/cloud-init.sh", {
    compose_file = "docker-compose-obs.yml", # Observability stack compose file
    REPO_URL     = var.repo_url
  }))
  tags                = merge(var.tags, { "Role" = "Observability" })
  instance_ocpus      = var.instance_ocpus
  instance_memory_in_gbs = var.instance_memory_in_gbs
}

# --- Storage: Frontend ---
resource "oci_objectstorage_bucket" "frontend_bucket" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = "${var.project_prefix}-frontend-bucket"
  access_type    = "ObjectReadWithoutList"
  freeform_tags  = var.tags
}

resource "oci_objectstorage_object" "frontend_index" {
  bucket       = oci_objectstorage_bucket.frontend_bucket.name
  namespace    = data.oci_objectstorage_namespace.ns.namespace
  object       = "index.html"
  content_type = "text/html"
  # O api_domain deve ser apontado para o IP público do Load Balancer
  content      = templatefile("../../../frontend/index.html", { api_endpoint = var.api_domain })
}

# --- Storage: InsumoPro (Acessível pela VM) ---
resource "oci_objectstorage_bucket" "insumopro_bucket" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = "${var.project_prefix}-insumopro"
  access_type    = "NoPublicAccess"
  freeform_tags  = var.tags
}

# --- Random Suffix for Unique Naming ---
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# --- IAM: Permissões para a VM acessar o Bucket ---
resource "oci_identity_dynamic_group" "backend_dg" {
  compartment_id = var.tenancy_ocid
  name           = "${var.project_prefix}-backend-dg-${random_string.suffix.result}"
  description    = "Grupo para a VM acessar o Object Storage"
  matching_rule  = "ALL {instance.compartment.id = '${var.compartment_ocid}', tag.Project.value = '${var.tags["Project"]}'}"
}

resource "oci_identity_policy" "backend_storage_policy" {
  compartment_id = var.compartment_ocid
  name           = "${var.project_prefix}-storage-policy"
  description    = "Permite a VM gerenciar objetos no bucket insumopro"

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.backend_dg.name} to manage objects in compartment id ${var.compartment_ocid} where target.bucket.name='${oci_objectstorage_bucket.insumopro_bucket.name}'"
  ]
}

# --- Load Balancer ---
resource "oci_load_balancer_load_balancer" "app_lb" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.project_prefix}-lb"
  shape          = "flexible"
  shape_details {
    minimum_bandwidth_in_mbps = 10
    maximum_bandwidth_in_mbps = 10
  }
  is_private = false
  subnet_ids = [module.network.public_subnet_id]
  freeform_tags = var.tags
}

# Backend Set para tráfego HTTP na porta 80
resource "oci_load_balancer_backend_set" "http_bs" {
  name             = "${var.project_prefix}-http-bs"
  load_balancer_id = oci_load_balancer_load_balancer.app_lb.id
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol    = "HTTP"
    port        = 80
    url_path    = "/health" # Endpoint de healthcheck do Traefik
    retries     = 2
    timeout_in_millis = 1000
    # interval_in_millis = 2000 # Temporariamente comentado para contornar o erro do provedor
  }
}

# Backend Set para tráfego TCP (HTTPS) na porta 443
resource "oci_load_balancer_backend_set" "https_bs" {
  name             = "${var.project_prefix}-https-bs"
  load_balancer_id = oci_load_balancer_load_balancer.app_lb.id
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol = "TCP" # Para HTTPS, um healthcheck TCP na porta é suficiente
    port     = 443
    retries  = 2
    timeout_in_millis = 1000
    # interval_in_millis = 2000 # Temporariamente comentado para contornar o erro do provedor
  }
}

# Adiciona as VMs ao Backend Set HTTP
resource "oci_load_balancer_backend" "http_backends" {
  count            = var.api_instance_count
  load_balancer_id = oci_load_balancer_load_balancer.app_lb.id
  backendset_name  = oci_load_balancer_backend_set.http_bs.name
  ip_address       = module.compute_api[count.index].private_ip
  port             = 80
}

# Adiciona as VMs ao Backend Set HTTPS
resource "oci_load_balancer_backend" "https_backends" {
  count            = var.api_instance_count
  load_balancer_id = oci_load_balancer_load_balancer.app_lb.id
  backendset_name  = oci_load_balancer_backend_set.https_bs.name
  ip_address       = module.compute_api[count.index].private_ip
  port             = 443
}

# Listener para HTTP na porta 80
resource "oci_load_balancer_listener" "http_listener" {
  load_balancer_id         = oci_load_balancer_load_balancer.app_lb.id
  name                     = "http"
  default_backend_set_name = oci_load_balancer_backend_set.http_bs.name
  port                     = 80
  protocol                 = "HTTP"
}

# Listener para TCP (HTTPS) na porta 443
resource "oci_load_balancer_listener" "https_listener" {
  load_balancer_id         = oci_load_balancer_load_balancer.app_lb.id
  name                     = "https"
  default_backend_set_name = oci_load_balancer_backend_set.https_bs.name
  port                     = 443
  protocol                 = "TCP" # Pass-through para o Traefik gerenciar o SSL
}

# --- Outputs ---
output "load_balancer_public_ip" {
  description = "Public IP address of the Load Balancer. Point your api_domain DNS record to this IP."
  value       = [for ip in oci_load_balancer_load_balancer.app_lb.ip_address_details : ip.ip_address if ip.is_public][0]
}

output "frontend_url" {
  description = "URL for the frontend hosted in OCI Object Storage."
  value       = "https://objectstorage.${var.region}.oraclecloud.com/n/${data.oci_objectstorage_namespace.ns.namespace}/b/${oci_objectstorage_bucket.frontend_bucket.name}/o/index.html"
}
 
output "ssh_commands" {
  description = "SSH commands to connect to each VM."
  value = {
    api_vms          = [for i in range(var.api_instance_count) : "ssh -i ${var.ssh_private_key_path} ubuntu@${module.compute_api[i].public_ip}"]
    observability_vm = var.create_observability_vm ? ["ssh -i ${var.ssh_private_key_path} ubuntu@${module.compute_obs[0].public_ip}"] : []
  }
  sensitive   = true
}

output "observability_vm_public_ip" {
  description = "Public IP of the Observability VM. Access Grafana at http://<IP>:3001"
  value       = var.create_observability_vm ? module.compute_obs[0].public_ip : "Not created."
}
