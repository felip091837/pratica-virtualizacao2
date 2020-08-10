#!/bin/bash

#felipesi
#sudo ./script.sh

IP_VM2='172.31.58.178'

mac_eth0=$(ifconfig eth0 | grep -i 'ether' | awk '{print $2}')

apt update
apt install qemu openvswitch-switch sshpass -y

wget http://download.cirros-cloud.net/0.5.1/cirros-0.5.1-x86_64-disk.img -O cirros.img
cp cirros.img red1.img
cp cirros.img green1.img

#cria interfaces TAP
ip tuntap add tap-red1 mode tap user ubuntu
ip tuntap add tap-green1 mode tap user ubuntu

#instancia as duas VMs
qemu-system-x86_64 -device e1000,netdev=user0 -netdev user,id=user0,hostfwd=tcp::2221-:22 -device e1000,netdev=net0,mac=00:00:00:00:00:01 -netdev tap,id=net0,ifname=tap-red1,script=no,downscript=no -m 256 -drive file=red1.img,media=disk,cache=writeback -vnc :1 -daemonize
qemu-system-x86_64 -device e1000,netdev=user0 -netdev user,id=user0,hostfwd=tcp::2222-:22 -device e1000,netdev=net0,mac=00:00:00:00:00:01 -netdev tap,id=net0,ifname=tap-green1,script=no,downscript=no -m 256 -drive file=green1.img,media=disk,cache=writeback -vnc :2 -daemonize

#aguarda ssh das VMs ser liberado
while true;do
    sshpass -p 'gocubsgo' ssh -oStrictHostKeyChecking=no cirros@localhost -p 2221 "echo" && sshpass -p 'gocubsgo' ssh -oStrictHostKeyChecking=no cirros@localhost -p 2222 "echo" && break
    sleep 1
done

#atribui o ip 192.168.0.1 a red-1 e 10.0.0.1 a green-1, na interface eth1
sshpass -p 'gocubsgo' ssh -oStrictHostKeyChecking=no cirros@localhost -p 2221 "sudo ip addr add 192.168.0.1/24 dev eth1"
sshpass -p 'gocubsgo' ssh -oStrictHostKeyChecking=no cirros@localhost -p 2222 "sudo ip addr add 10.0.0.1/24 dev eth1"

#Habilita a interface eth1 nas duas VMs
sshpass -p 'gocubsgo' ssh -oStrictHostKeyChecking=no cirros@localhost -p 2221 "sudo ip link set eth1 up"
sshpass -p 'gocubsgo' ssh -oStrictHostKeyChecking=no cirros@localhost -p 2222 "sudo ip link set eth1 up"

#habilita interfaces TAP
ip link set tap-red1 up
ip link set tap-green1 up

#cria bridge br-red e br-green
ovs-vsctl --may-exist add-br br-red -- set Bridge br-red datapath_type=netdev -- br-set-external-id br-red bridge-id br-red -- set bridge br-red fail-mode=standalone
ovs-vsctl --may-exist add-br br-green -- set Bridge br-green datapath_type=netdev -- br-set-external-id br-green bridge-id br-green -- set bridge br-green fail-mode=standalone

#adiciona tap-red1 a br-red e tap-green1 a br-green
ovs-vsctl add-port br-red tap-red1
ovs-vsctl add-port br-green tap-green1

#adiciona interface VTEP a br-red e a br-green
ovs-vsctl add-port br-red vxlan0 -- set interface vxlan0 type=vxlan options:remote_ip=$IP_VM2 options:key=9001 options:dst_port=9001
ovs-vsctl add-port br-green vxlan1 -- set interface vxlan1 type=vxlan options:remote_ip=$IP_VM2 options:key=9002 options:dst_port=9002

#cria interface br-phy
ovs-vsctl --may-exist add-br br-phy -- set Bridge br-phy datapath_type=netdev -- br-set-external-id br-phy bridge-id br-phy -- set bridge br-phy fail-mode=standalone other_config:hwaddr=$mac_eth0

#adiciona eth0 a br-phy
ovs-vsctl --timeout 10 add-port br-phy eth0

#configura o netplan
cat <<EOT > /etc/netplan/50-cloud-init.yaml
network:
    version: 2
    ethernets:
        eth0:
            dhcp4: false
        br-phy:
            dhcp4: true
EOT

netplan apply