terraform {
    required_providers {
      proxmox = {
	    source = "bpg/proxmox"
	    version = ">=0.50.0"
	  }
  }
}

variable "proxmox_endpoint" {
    sensitive = true
}

variable "proxmox_api_token" {
    sensitive = true
}


provider "proxmox" {
    endpoint= var.proxmox_endpoint
    api_token= var.proxmox_api_token
    insecure = true
}


###### ELASTICSEARCH VM ##############################################################
resource "proxmox_virtual_environment_vm" "elasticsearch" {
    name = "elasticsearch"
    node_name= "pve"
  clone {
    vm_id = 9000
  }
  cpu {
    cores = 2
  }
  memory {
    dedicated = 4096
  }
  disk {
    datastore_id = "local-lvm"
    interface = "virtio0"
    size = 96
  }
  network_device {
    bridge = "vmbr2"
  }
  initialization {
    ip_config {
	    ipv4 {
	      address="192.168.1.10"
	    }
    }
    user_account {
	    username= "tom"
	    keys = [
	      file("~/.ssh/proxmox.pub")
	    ]

	  }
  }
}

###### KIBANA VM ##############################################################
resource "proxmox_virtual_environment_vm" "kibana" {
    name = "kibana"
    node_name= "pve"
  clone {
    vm_id = 9000
  }
  cpu {
    cores = 2
  }
  memory {
    dedicated = 2048
  }
  disk {
    datastore_id = "local-lvm"
    interface = "virtio0"
    size = 20
  }
  network_device {
    bridge = "vmbr2"
  }
  initialization {
    ip_config {
  	  ipv4 {
	      address="192.168.1.20"
  	  }
    } 
    user_account {
    	username= "tom"
	    keys = [
	      file("~/.ssh/proxmox.pub")
	    ]
	  }
  }
}
