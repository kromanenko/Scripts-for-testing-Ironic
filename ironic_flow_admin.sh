#! /bin/bash

# Setup and run virtual Ironic instance with admin rights
set -e

# source openrc
source ~/openrc

# Declare local variables
SSH_ADDRESS=xxx.xxx.xxx.xxx
VIRTUAL_NODE_MAC=00:00:00:00:00:00

function virt_flavor_create {
	nova flavor-create bm_flavor auto 3072 150 1
	nova flavor-key bm_flavor set cpu_arch=x86_64
}

function get_image {
	curl https://cloud-images.ubuntu.com/trusty/current/trusty-server-cloudimg-amd64.tar.gz | tar -xzp
}

function virtual_img_create {
	glance --os-image-api-version 1 \
	image-create \
	--name virtual_trusty_ext4 \
	--disk-format raw \
	--container-format bare \
	--file trusty-server-cloudimg-amd64.img \
	--is-public True \
	--progress \
	--property cpu_arch='x86_64' \
	--property hypervisor_type='baremetal' \
	--property fuel_disk_info='[{"name": "vda", "extra": [], "free_space": 11000, "type": "disk", "id": "vda", "size": 11000, "volumes": [{"mount": "/", "type": "partition", "file_system": "ext4", "size": 10000}]}]'
}

function key_create {
	nova keypair-add ironic_key > ironic_key.pem
	chmod 600 ironic_key.pem
}

function get_image_info {
	OUTPUT="$(glance image-list)"
	kernel_id="$(echo "$OUTPUT" | grep ironic-deploy-linux | awk '{print $2}')"
	ramdisk_id="$(echo "$OUTPUT" | grep ironic-deploy-initramfs | awk '{print $2}')"
	squashfs_id="$(echo "$OUTPUT" | grep ironic-deploy-squashfs | awk '{print $2}')"
	echo "Kernel image ID is $kernel_id"
	echo "Ramdisk image ID is $ramdisk_id"
	echo "Squashfs image ID is $squashfs_id"
}

function virtual_node_create {
	ironic node-create \
	-n virtual \
	-d fuel_ssh \
	-i deploy_kernel="$kernel_id" \
	-i deploy_ramdisk="$ramdisk_id" \
	-i deploy_squashfs="$squashfs_id" \
	-i ssh_address="$SSH_ADDRESS" \
	-i ssh_password=ironic_password \
	-i ssh_username=ironic \
	-i ssh_virt_type=virsh \
	-p cpus=1 \
	-p memory_mb=3072 \
	-p local_gb=150 \
	-p cpu_arch=x86_64
}

function get_node_id {
	virt_node_id="$(ironic node-show virtual | grep ' uuid ' | awk '{print $4}')"
	echo "Node ID is $virt_node_id"
}

function get_net_id {
	OUTPUT="$(nova net-list)"
	net_id=$(echo "$OUTPUT" | grep baremetal | awk '{print $2}')
}

function virtual_port_create {
	ironic port-create \
	-n "$virt_node_id" \
	-a "$VIRTUAL_NODE_MAC"
}

function virtual_boot {
	nova boot \
	--flavor bm_flavor \
	--image virtual_trusty_ext4 \
	--key-name ironic_key \
	--nic net-id="$net_id" \
	UbuntuVM
}

function wait_boot {
	Status="none"
	until [ "$Status" == "ACTIVE" ] || [ "$Status" == "ERROR" ]
	do
	sleep 60
	Status="$(nova show UbuntuVM | grep status | awk '{print $4}')"
	if [ -z "$Status" ]; then break; fi
	echo "Status is $Status"
	done
}

virt_flavor_create
get_image
virtual_img_create
key_create
get_image_info
virtual_node_create
get_node_id
get_net_id
virtual_port_create
sleep 180
virtual_boot
wait_boot

