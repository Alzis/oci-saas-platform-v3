output "public_subnet_id" {
  description = "The OCID of the public subnet."
  value       = oci_core_subnet.public.id
}

output "app_nsg_id" {
  description = "The OCID of the application Network Security Group."
  value       = oci_core_network_security_group.app_nsg.id
}

output "private_subnet_id" {
  description = "The OCID of the private subnet."
  value       = oci_core_subnet.private.id
}

output "db_nsg_id" {
  description = "The OCID of the database Network Security Group."
  value       = oci_core_network_security_group.db_nsg.id
}

output "private_subnet_dns_label" {
  description = "The DNS label of the private subnet."
  value       = oci_core_subnet.private.dns_label
}

output "vcn_dns_label" {
  description = "The DNS label of the VCN."
  value       = oci_core_vcn.main.dns_label
}