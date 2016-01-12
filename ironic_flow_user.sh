#! /bin/bash
# This version of script is for non-admin instance booting

set -e

# source openrc
source ~/openrc

# Declare local variables
SSH_ADDRESS="xxx.xxx.xxx.xxx"
VIRTUAL_NODE_MAC="00:00:00:00:00:00"

function virt_flavor_create {
	nova flavor-create bm_flavor auto 3072 150 1
	nova flavor-key bm_flavor set cpu_arch=x86_64
}

function get_image {
	curl https://cloud-images.ubuntu.com/trusty/current/trusty-server-cloudimg-amd64.tar.gz | tar -xzp
}

function switch_to_user {
	export OS_USERNAME='demo'
	export OS_PASSWORD='demo'
	export OS_TENANT_NAME='demo'
	export OS_PROJECT_NAME='demo'
}

function create_user {
# Create non-admin tenant and user and apply it`s credentials
	keystone tenant-create --name demo
	keystone user-create --name demo --tenant demo --pass demo
	sleep 5
	switch_to_user
	sleep 5
# Create keypair for non-admin user
	nova keypair-add ironic_key_user > ironic_key_user.pem
	chmod 600 ironic_key_user.pem
}

function virtual_img_create {
	glance --os-image-api-version 1 \
	image-create \
	--name virtual_trusty_ext4_user \
	--disk-format raw \
	--container-format bare \
	--file trusty-server-cloudimg-amd64.img \
	--progress \
	--property cpu_arch='x86_64' \
	--property hypervisor_type='baremetal' \
	--property mos_disk_info='[{"name": "vda", "extra": [], "free_space": 11000, "type": "disk", "id": "vda", "size": 11000, "volumes": [{"mount": "/", "type": "partition", "file_system": "ext4", "size": 10000}]}]'
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
	port_id="$(ironic port-create \
	-n "$virt_node_id" \
	-a "$VIRTUAL_NODE_MAC" | grep ' uuid ' | awk '{print $4}')"
	echo "Port ID is $port_id"
}

function virtual_boot {
	echo "This is file injection" > injection.txt
	nova boot \
	--flavor bm_flavor \
	--image virtual_trusty_ext4_user \
	--key-name ironic_key_user \
	--nic net-id="$net_id" \
	--user-data ./injection.txt \
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

function floating_ip_create {
	floating_ip="$(nova floating-ip-create | grep admin_floating_net | awk '{print $4}')"
	echo "Floating IP is $floating_ip"
}

function floating_ip_associate {
	nova floating-ip-associate UbuntuVM "$floating_ip"
}

function ssh_to_machine {
	ssh -i ironic_key_user.pem "ubuntu@$floating_ip" -q "cat injection.txt" || true
}

function records_for_cleanup {
	source ~/openrc
	> cleanup.txt
	echo "| Floating-IP | $floating_ip |" >> cleanup.txt
	echo "| Instance | UbuntuVM |" >> cleanup.txt
	echo "| Port-ID | $port_id|" >> cleanup.txt
	echo "| Node-ID | $virt_node_id |" >> cleanup.txt
	echo "| Image | virtual_trusty_ext4_user |" >> cleanup.txt
	echo "| Flavor | bm_flavor |" >> cleanup.txt
}

virt_flavor_create
get_image
create_user
virtual_img_create
source ~/openrc
get_image_info
virtual_node_create
get_node_id
get_net_id
virtual_port_create
sleep 180

switch_to_user

virtual_boot
wait_boot

floating_ip_create
floating_ip_associate
ssh_to_machine
records_for_cleanup
echo "Done"

