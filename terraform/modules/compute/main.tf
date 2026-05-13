data "oci_core_images" "ubuntu" {
  # For platform images, compartment_id must be the tenancy OCID.
  compartment_id           = var.tenancy_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_instance" "app_vm" {
  compartment_id      = var.compartment_id
  availability_domain = var.availability_domain
  display_name        = "${var.project_prefix}-vm"
  shape               = var.instance_shape

  dynamic "shape_config" {
    for_each = strcontains(var.instance_shape, ".Flex") ? [1] : []
    content {
      ocpus         = var.instance_ocpus
      memory_in_gbs = var.instance_memory_in_gbs
    }
  }

  freeform_tags       = var.tags

  create_vnic_details {
    subnet_id              = var.subnet_id
    assign_public_ip       = true
    nsg_ids                = [var.nsg_id]
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = var.user_data_base64
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu.images[0].id
  }

  lifecycle {
    ignore_changes = [
      # Ignora mudanças no user_data após a criação inicial
      # para evitar reprovisionamento em cada 'apply'.
      metadata["user_data"],
    ]
  }
}