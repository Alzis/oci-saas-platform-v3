resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_id
  cidr_block     = var.vcn_cidr
  display_name   = "${var.project_prefix}-vcn"
  dns_label      = replace(var.project_prefix, "-", "")
  freeform_tags  = var.tags
}

resource "oci_core_nat_gateway" "nat_gw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_prefix}-nat-gw"
  freeform_tags  = var.tags
  # No need for enabled = true, it's implicitly enabled on creation
}

resource "oci_core_internet_gateway" "gw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_prefix}-igw"
  enabled        = true
  freeform_tags  = var.tags
}

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

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_prefix}-private-rt"
  freeform_tags  = var.tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.nat_gw.id
  }

}

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

resource "oci_core_subnet" "private" {
  compartment_id      = var.compartment_id
  vcn_id              = oci_core_vcn.main.id
  cidr_block          = var.private_subnet_cidr
  display_name        = "${var.project_prefix}-private-subnet"
  dns_label           = "private"
  route_table_id      = oci_core_route_table.private.id
  prohibit_public_ip_on_vnic = true # Private subnet, no public IPs
  freeform_tags       = var.tags
}

resource "oci_core_network_security_group" "app_nsg" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_prefix}-app-nsg"
  freeform_tags  = var.tags
}

resource "oci_core_network_security_group" "db_nsg" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_prefix}-db-nsg"
  freeform_tags  = var.tags
}

resource "oci_core_network_security_group" "obs_nsg" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_prefix}-obs-nsg"
  freeform_tags  = var.tags
}

# Regra para acesso SSH
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

# Regra para acesso Web (HTTP/HTTPS)
resource "oci_core_network_security_group_security_rule" "allow_web" {
  network_security_group_id = oci_core_network_security_group.app_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = var.vcn_cidr # Permite tráfego do Load Balancer dentro da VCN
  source_type               = "CIDR_BLOCK"
  description               = "Allow HTTP access from within the VCN (for Load Balancer)"
  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}

resource "oci_core_network_security_group_security_rule" "allow_web_secure" {
  network_security_group_id = oci_core_network_security_group.app_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = var.vcn_cidr # Permite tráfego do Load Balancer dentro da VCN
  source_type               = "CIDR_BLOCK"
  description               = "Allow HTTPS access from within the VCN (for Load Balancer)"
  tcp_options {
    destination_port_range {
      min = 443
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

# SSH para a VM de Observabilidade
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

# Acesso ao Grafana
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

# Saída para a VM de Observabilidade
resource "oci_core_network_security_group_security_rule" "allow_all_egress_obs" {
  network_security_group_id = oci_core_network_security_group.obs_nsg.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  description               = "Allow all outbound traffic from Observability VM"
}

# --- Regras entre NSGs ---

# Regra para permitir que as VMs (no NSG da app) acessem o DB (no NSG do DB)
resource "oci_core_network_security_group_security_rule" "allow_app_to_db" {
  network_security_group_id = oci_core_network_security_group.db_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source_type               = "NETWORK_SECURITY_GROUP"
  source                    = oci_core_network_security_group.app_nsg.id # Permite tráfego do NSG da aplicação
  description               = "Allow app VMs to connect to DB"
  tcp_options {
    destination_port_range {
      min = 5432 # Porta padrão do PostgreSQL
      max = 5432
    }
  }
}

# Regra de saída para o DB (opcional, mas boa prática para atualizações)
resource "oci_core_network_security_group_security_rule" "allow_db_egress" {
  network_security_group_id = oci_core_network_security_group.db_nsg.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  description               = "Allow all outbound traffic from DB (e.g., for updates)"
}

output "obs_nsg_id" {
  description = "The OCID of the Network Security Group for the Observability VM."
  value       = oci_core_network_security_group.obs_nsg.id
}
