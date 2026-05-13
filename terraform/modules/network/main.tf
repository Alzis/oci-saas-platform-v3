resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_id
  cidr_block     = var.vcn_cidr
  display_name   = "${var.project_prefix}-vcn"
  dns_label      = replace(var.project_prefix, "-", "")
  freeform_tags  = var.tags
}

resource "oci_core_internet_gateway" "gw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_prefix}-igw"
  enabled        = true
  freeform_tags  = var.tags
}
# Tabela de Rota Pública
resource "oci_core_route_table" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_prefix}-rt"
  freeform_tags  = var.tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.gw.id
  }
}

# Subnet Pública Única
resource "oci_core_subnet" "public" {
  compartment_id      = var.compartment_id
  vcn_id              = oci_core_vcn.main.id
  cidr_block          = var.subnet_cidr
  display_name        = "${var.project_prefix}-public-subnet"
  dns_label           = "public"
  route_table_id      = oci_core_route_table.main.id
  prohibit_public_ip_on_vnic = false
  freeform_tags       = var.tags
}

# --- Grupos de Segurança de Rede (NSG) ---
resource "oci_core_network_security_group" "app_nsg" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_prefix}-app-nsg"
  freeform_tags  = var.tags
}

resource "oci_core_network_security_group" "obs_nsg" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_prefix}-obs-nsg"
  freeform_tags  = var.tags
}

# --- Regras para o NSG da Aplicação ---
resource "oci_core_network_security_group_security_rule" "allow_ssh" {
  network_security_group_id = oci_core_network_security_group.app_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = var.ssh_source_cidr
  source_type               = "CIDR_BLOCK"
  description               = "Allow SSH access"
  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

# Regra para permitir tráfego do Load Balancer (HTTP/HTTPS)
resource "oci_core_network_security_group_security_rule" "allow_web" {
  network_security_group_id = oci_core_network_security_group.app_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "0.0.0.0/0" # O LB encaminhará o tráfego. A porta 80 é necessária para o desafio ACME do Let's Encrypt.
  source_type               = "CIDR_BLOCK"
  description               = "Allow HTTP/S traffic, primarily for Traefik (ACME challenge and service)"
  tcp_options {
    destination_port_range {
      min = 80
      max = 443
    }
  }
}

# Regra de SAÍDA (Egress) - Essencial para baixar o Docker e atualizações
resource "oci_core_network_security_group_security_rule" "allow_all_egress" {
  network_security_group_id = oci_core_network_security_group.app_nsg.id
  direction                 = "EGRESS"
  protocol                  = "all" # Permite todos os protocolos de saída
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  description               = "Allow all outbound traffic"
}

# --- Regras para o NSG de Observabilidade ---
resource "oci_core_network_security_group_security_rule" "allow_ssh_obs" {
  network_security_group_id = oci_core_network_security_group.obs_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = var.ssh_source_cidr
  source_type               = "CIDR_BLOCK"
  description               = "Allow SSH access to Observability VM"
  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

resource "oci_core_network_security_group_security_rule" "allow_grafana" {
  network_security_group_id = oci_core_network_security_group.obs_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "0.0.0.0/0" # Ou restrinja para seu IP
  source_type               = "CIDR_BLOCK"
  description               = "Allow access to Grafana dashboard"
  tcp_options {
    destination_port_range {
      min = 3001 # Porta exposta no docker-compose
      max = 3001
    }
  }
}

resource "oci_core_network_security_group_security_rule" "allow_all_egress_obs" {
  network_security_group_id = oci_core_network_security_group.obs_nsg.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  description               = "Allow all outbound traffic from Observability VM"
}
