output "private_ip" {
  description = "The private IP address of the compute instance."
  value       = oci_core_instance.app_vm.private_ip
}

output "public_ip" {
  description = "The public IP address of the compute instance."
  value       = oci_core_instance.app_vm.public_ip
}
