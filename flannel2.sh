#
# based on flannel1.sh but
# use different IP subnet (10.246.0.0/16) for containers from flannel subnet
#

set -x

# set up 3 namespaces with diff hostnames

unshare --net --uts -r /bin/bash &
export pid_netns1=$!
sudo nsenter -t $pid_netns1 -u hostname netns1
unshare --net --uts -r /bin/bash &
export pid_netns2=$!
sudo nsenter -t $pid_netns2 -u hostname netns2
unshare --net --uts -r /bin/bash &
export pid_netns3=$!
sudo nsenter -t $pid_netns3 -u hostname netns3

# set up bridge and veth links

sudo ip link add ens192 netns $pid_netns1 type veth peer name eth1 netns $pid_netns3
sudo ip link add ens192 netns $pid_netns2 type veth peer name eth2 netns $pid_netns3

sudo nsenter -t $pid_netns3 -u -n /bin/bash -c "
  brctl addbr brx  
  ip link set brx up
  "

# set up L3

sudo nsenter -t $pid_netns1 -u -n /bin/bash -c "
  ip addr add 192.168.5.1/24 brd 192.168.5.255 dev ens192
  ip link set ens192 up
  ip link set lo up
  ip a s
  "
sudo nsenter -t $pid_netns2 -u -n /bin/bash -c "
  ip addr add 192.168.5.2/24 brd 192.168.5.255 dev ens192
  ip link set ens192 up
  ip link set lo up
  ip a s
  "

# finish bridge setup

sudo nsenter -t $pid_netns3 -u -n /bin/bash -c "
  ip link set eth1 up
  ip link set eth2 up
  brctl addif brx eth1
  brctl addif brx eth2
  "

# vxlan setup

sudo nsenter -t $pid_netns1 -u -n /bin/bash -c "
  ip link add vxlan1 type vxlan id 100 dstport 8472 local 192.168.5.1 nolearning
  "
export vxlan1_vtep=$(sudo nsenter -t $pid_netns1 -u -n /bin/bash -c "ip link show vxlan1" | grep ether | awk '{print $2}')
echo $vxlan1_vtep

sudo nsenter -t $pid_netns2 -u -n /bin/bash -c "
  ip link add vxlan2 type vxlan id 100 dstport 8472 local 192.168.5.2 nolearning
  "
export vxlan2_vtep=$(sudo nsenter -t $pid_netns2 -u -n /bin/bash -c "ip link show vxlan2" | grep ether | awk '{print $2}')
echo $vxlan2_vtep

sudo nsenter -t $pid_netns1 -u -n /bin/bash -c "
  ip neigh add 10.245.1.0 lladdr $vxlan2_vtep dev vxlan1 
  bridge fdb append $vxlan2_vtep dev vxlan1 dst 192.168.5.2
  "
sudo nsenter -t $pid_netns1 -u -n /bin/bash -c "
  ip l set vxlan1 up
  ip -d link show vxlan1
  ip addr add 10.245.0.0/32 dev vxlan1
  ip route add 10.245.1.0/24 via 10.245.1.0 dev vxlan1 onlink
  "

sudo nsenter -t $pid_netns2 -u -n /bin/bash -c "
  ip neigh add 10.245.0.0 lladdr $vxlan1_vtep dev vxlan2
  bridge fdb append $vxlan1_vtep dev vxlan2 dst 192.168.5.1
  "
sudo nsenter -t $pid_netns2 -u -n /bin/bash -c "
  ip l set vxlan2 up
  ip -d l show vxlan2
  ip addr add 10.245.1.0/32 dev vxlan2
  ip route add 10.245.0.0/24 via 10.245.0.0 dev vxlan2 onlink
  "

# set up container-like netns in host 1

unshare --net --uts -r /bin/bash &
export pid_netns4=$!
sudo nsenter -t $pid_netns4 -u hostname netns4
unshare --net --uts -r /bin/bash &
export pid_netns5=$!
sudo nsenter -t $pid_netns5 -u hostname netns5

# set up bridge and veth links

sudo ip link add eth0 netns $pid_netns4 type veth peer name veth14 netns $pid_netns1
sudo ip link add eth0 netns $pid_netns5 type veth peer name veth15 netns $pid_netns1

sudo nsenter -t $pid_netns1 -u -n /bin/bash -c "
  brctl addbr cni0  
  ip link set cni0 up
  "

# set up L3

sudo nsenter -t $pid_netns4 -u -n /bin/bash -c "
  ip addr add 10.246.0.4/24 brd 10.246.0.255 dev eth0
  ip link set eth0 up
  ip link set lo up
  ip a s
  ip route add default via 10.246.0.1 dev eth0
  "
sudo nsenter -t $pid_netns5 -u -n /bin/bash -c "
  ip addr add 10.246.0.5/24 brd 10.246.0.255 dev eth0
  ip link set eth0 up
  ip link set lo up
  ip a s
  ip route add default via 10.246.0.1 dev eth0
  "

# finish bridge setup

sudo nsenter -t $pid_netns1 -u -n /bin/bash -c "
  ip link set veth14 up
  ip link set veth15 up
  brctl addif cni0 veth14
  brctl addif cni0 veth15
  ip addr add 10.246.0.1/24 brd 10.246.0.255 dev cni0
  ip link set cni0 up
  ip link set lo up
  ip a s
  ip route add 10.246.1.0/24 via 10.245.1.0 dev vxlan1 onlink
  ip route add 10.246.0.0/24 dev cni0
  # allow IP forwarding
  echo 1 > /proc/sys/net/ipv4/conf/all/forwarding
  # optional SNAT
  iptables -t nat -A POSTROUTING -o vxlan1 -j SNAT --to 10.245.0.0
  "

sudo nsenter -t $pid_netns2 -u -n /bin/bash -c "
  ip route add 10.246.0.0/24 via 10.245.0.0 dev vxlan2 onlink
  "
set +x

echo "export pid_netns1=$pid_netns1"
echo "export pid_netns2=$pid_netns2"
echo "export pid_netns3=$pid_netns3"
echo "export pid_netns4=$pid_netns4"
echo "export pid_netns5=$pid_netns5"
echo "export pid_netns6=$pid_netns6"
echo "export pid_netns7=$pid_netns7"

