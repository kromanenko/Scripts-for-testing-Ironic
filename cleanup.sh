#! /bin/bash

set -v

source ~/openrc
export OS_USERNAME='demo'
export OS_PASSWORD='demo'
export OS_TENANT_NAME='demo'
export OS_PROJECT_NAME='demo'

floating_ip="$(cat cleanup.txt | grep "Floating-IP" | awk '{print $4}')"
instance="$(cat cleanup.txt | grep "Instance" | awk '{print $4}')"
port_id="$(cat cleanup.txt | grep "Port-ID" | awk '{print $4}')"
node_id="$(cat cleanup.txt | grep "Node-ID" | awk '{print $4}')"
image="$(cat cleanup.txt | grep "Image-ID" | awk '{print $4}')"
flavor="$(cat cleanup.txt | grep "Flavor" | awk '{print $4}')"

echo $floating_ip
echo $instance
echo $port_id
echo $node_id
echo $image
echo $flavor

nova floating-ip-disassociate $instance $floating_ip
nova delete $instance
source ~/openrc
ironic port-delete $port_id
ironic node-delete $node_id
glance image-delete $image
nova flavor-delete $flavor
keystone user-delete demo
keystone tenant-delete demo

echo "Cleanup done!"

