terraform {
    required_version = ">= 1.15.2"
    
    required_providers {
	proxmox = {
	    source = "bpg/proxmox"
      version = "~> 0.106.0"
    }
  }
}

###############################################################################
# Provider ####################################################################
###############################################################################
provider "proxmox" {
  endpoint = var.proxmox_api_url
  api_token = "${var.proxmox_token_id}=${var.proxmox_token_secret}"
  insecure = true

}

###############################################################################
# Variables ###################################################################
###############################################################################
variable "proxmox_api_url" {
  type = string
  sensitive = true
}

variable "proxmox_token_id" {
  type = string
  sensitive = true
}

variable "proxmox_token_secret" {
  type      = string
  sensitive = true
}

variable "target_node" {
  type    = string
  default = "proxmox"
}

variable "vm_storage" {
  type    = string
  default = "local-lvm"
}

variable "cloudinit_storage" {
  type    = string
  default = "local-lvm"
}

variable "template_name" {
  type    = string
  default = "Alma9"
}

variable "ssh_public_key" {
  type = string
}

variable "gateway" {
  type    = string
  default = "192.168.1.1"

}

###############################################################################
# VM Definitions ##############################################################
###############################################################################

locals {
  kubernetes_nodes = {
    k8s-control-01 = {
      vm_id   = 501
      ip      = "192.168.1.101/24"
      cores   = 2
      memory  = 4096
      disk_gb = 40
    }

    k8s-worker-01 = {
      vm_id   = 502
      ip      = "192.168.1.102/24"
      cores   = 2
      memory  = 4096
      disk_gb = 60
    }

    k8s-worker-02 = {
      vm_id   = 503
      ip      = "192.168.1.103/24"
      cores   = 2
      memory  = 4096
      disk_gb = 60
    }
  }
}

###############################################################################
# Virtual Machines ############################################################
###############################################################################

resource "proxmox_virtual_environment_vm" "k8s_nodes" {
  for_each = local.kubernetes_nodes
  name      = each.key
  node_name = var.target_node
  vm_id     = each.value.vm_id
  tags = ["terraform", "kubernetes", "elasticsearch"]
    
  agent {
    enabled = true
  }
  cpu {
    cores = each.value.cores
    type  = "host"
  }
  memory {
    dedicated = each.value.memory
  }
  
  initialization {
    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = var.gateway
      }
    }
    user_account {
      username = "ubuntu"
      keys = [
        var.ssh_public_key
      ]
    }
  }
  
  disk {
    interface    = "scsi0"
    datastore_id = var.vm_storage
    import_from  = proxmox_download_file.ubuntu_cloud_image.id
    size         = each.value.disk_gb
    iothread     = true
    discard      = "on"
    ssd           = true
  }

  network_device {
    bridge = "vmbr2"
    model  = "virtio"
  }
  operating_system {
    type = "l26"
  }
  machine = "q35"
  bios    = "ovmf"
  on_boot = true
  started = true
}

###############################################################################
# Cloud Image #################################################################
###############################################################################


resource "proxmox_download_file" "ubuntu_cloud_image" {
  content_type = "import"
  datastore_id = "local"
  node_name    = var.target_node
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  # need to rename the file to *.qcow2 to indicate the actual file format for import
  file_name = "noble-server-cloudimg-amd64.qcow2"
}

###############################################################################
# Lookup Existing Template ####################################################
###############################################################################

variable "template_vm_id" {
  type = number
  default = 9000
}


###############################################################################
# Outputs #####################################################################
###############################################################################

output "vm_ips" {
  value = {
    for vm_name, vm in local.kubernetes_nodes :
    vm_name => vm.ip
  }
}    
