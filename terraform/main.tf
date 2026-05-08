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


###### CONTROL PLANE ##############################################################
resource "proxmox_virtual_environment_vm" "control-plane" {
    name = "control"
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
    mac_address = "02:00:00:00:10:01"
  }
  network_device {
    bridge = "vmbr3"
  }
  initialization {
    ip_config {
	    ipv4 {
	      address="192.168.1.10/24"
        gateway="192.168.1.1"
	    }
    }
    ip_config {
        ipv4 {
          address="192.168.100.10/24"
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

###### Worker 1 ##############################################################
resource "proxmox_virtual_environment_vm" "worker1" {
    name = "worker1"
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
    size = 40
  }
  network_device {
    bridge = "vmbr3"
  }
  network_device {
      bridge = "vmbr2"
  }
  initialization {
    ip_config {
  	  ipv4 {
	      address="192.168.100.100"
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

###### Worker 2 ##############################################################
resource "proxmox_virtual_environment_vm" "worker2" {
    name = "worker2"
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
    size = 40
  }
  network_device {
    bridge = "vmbr3"
  }
  network_device {
    bridge = "vmbr2"
  }

  initialization {
    ip_config {
  	  ipv4 {
	      address="192.168.100.101"
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
