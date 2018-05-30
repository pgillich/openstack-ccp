## Synopsis
* **do_osa.sh**
This bash based ochrestator tries to deploy openstack queens with monasca integrated in a virtualized environment. The setup is based on Openstack-ansible.
* **do_osh.sh**
This bash based ochrestator tries to deploy openstack on top of kubernets in a virtualized environment. The setup is based on Openstack-helm.

## Architecture
### Openstack-ansible
The deployed system contains 2 computes, one infra node, one log and one storage one. There is a virtual trunked network called 'bus'.
within bus
* **VLAN tag 10** is the control network
* **VLAN tag 30** is the tunnel/overlay one for tenant traffic
* **VLAN tag 20** is the storage network
### Openstack-helm
The deployed system contains 1 kubernetes master and 4 worker nodes. The infrastructure nodes are in the 172.16.0.0/16 newtork

## Installation
The installation requires
* libvirt-bin
* qemu-keymaps
* qemu-kvm
* qemu-system-common
* qemu-system-x86
* qemu-utils
* cloud-image-utils
ubuntu packages

The Hypervisor OS is preferably ubuntu server, the cpu should have at least 8 cores, 64GBytes memory, the user should have 200 GBytes room in the home folder.
