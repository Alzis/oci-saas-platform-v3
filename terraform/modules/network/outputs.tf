output "public_subnet_id" {
  description = "The OCID of the public subnet."
  value       = oci_core_subnet.public.id
}

output "app_nsg_id" {
  description = "The OCID of the application Network Security Group."
  value       = oci_core_network_security_group.app_nsg.id
}

output "obs_nsg_id" {
  description = "The OCID of the Network Security Group for the Observability VM."
  value       = oci_core_network_security_group.obs_nsg.id
}

output "vcn_dns_label" {
  description = "The DNS label of the VCN."
  value       = oci_core_vcn.main.dns_label
}