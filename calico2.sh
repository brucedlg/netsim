#
# simulate kubernetes calico networking data plane
#
# without using 169.254.1.1 gateway
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

# tunl0 setup

sudo modprobe -v ipip

sudo nsenter -t $pid_netns1 -u -n /bin/bash -c "
  ip link set tunl0 up
  ip link set tunl0 mtu 1480
  ip addr add 10.245.0.0/32 dev tunl0
  ip route add 10.245.1.0/24 via 192.168.5.2 dev tunl0 onlink
  "

sudo nsenter -t $pid_netns2 -u -n /bin/bash -c "
  ip link set tunl0 up
  ip link set tunl0 mtu 1480
  ip addr add 10.245.1.0/32 dev tunl0
  ip route add 10.245.0.0/24 via 192.168.5.1 dev tunl0 onlink
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

# set up L3

sudo nsenter -t $pid_netns4 -u -n /bin/bash -c "
  ip addr add 10.245.0.4/32 dev eth0
  ip link set eth0 up
  ip link set lo up
  ip a s
  ip route add default dev eth0
  "
sudo nsenter -t $pid_netns5 -u -n /bin/bash -c "
  ip addr add 10.245.0.5/32 dev eth0
  ip link set eth0 up
  ip link set lo up
  ip a s
  ip route add default dev eth0
  "

# finish bridge setup

sudo nsenter -t $pid_netns1 -u -n /bin/bash -c "
  ip link set veth14 up
  ip link set veth15 up
  ip link set lo up
  ip a s
  # allow IP forwarding
  echo 1 > /proc/sys/net/ipv4/conf/all/forwarding
  echo 1 > /proc/sys/net/ipv4/conf/veth14/proxy_arp
  echo 1 > /proc/sys/net/ipv4/conf/veth15/proxy_arp
  # optional SNAT
  # iptables -t nat -A POSTROUTING -o vxlan1 -j SNAT --to 10.245.0.0
  ip route add 10.245.0.4/32 dev veth14 scope link
  ip route add 10.245.0.5/32 dev veth15 scope link
  ip route add default dev ens192
  "

# set up container-like netns in host 2

unshare --net --uts -r /bin/bash &
export pid_netns6=$!
sudo nsenter -t $pid_netns6 -u hostname netns6
unshare --net --uts -r /bin/bash &
export pid_netns7=$!
sudo nsenter -t $pid_netns7 -u hostname netns7

# set up bridge and veth links

sudo ip link add eth0 netns $pid_netns6 type veth peer name veth26 netns $pid_netns2
sudo ip link add eth0 netns $pid_netns7 type veth peer name veth27 netns $pid_netns2

# set up L3

sudo nsenter -t $pid_netns6 -u -n /bin/bash -c "
  ip addr add 10.245.1.6/32 dev eth0
  ip link set eth0 up
  ip link set lo up
  ip a s
  ip route add default dev eth0
  "
sudo nsenter -t $pid_netns7 -u -n /bin/bash -c "
  ip addr add 10.245.1.7/32 dev eth0
  ip link set eth0 up
  ip link set lo up
  ip a s
  ip route add default dev eth0
  "

# finish bridge setup

sudo nsenter -t $pid_netns2 -u -n /bin/bash -c "
  ip link set veth26 up
  ip link set veth27 up
  ip link set lo up
  ip a s
  # allow IP forwarding
  echo 1 > /proc/sys/net/ipv4/conf/all/forwarding
  echo 1 > /proc/sys/net/ipv4/conf/veth26/proxy_arp
  echo 1 > /proc/sys/net/ipv4/conf/veth27/proxy_arp
  # optional SNAT
  # iptables -t nat -A POSTROUTING -o vxlan1 -j SNAT --to 10.245.1.0
  ip route add 10.245.1.6/32 dev veth26 scope link
  ip route add 10.245.1.7/32 dev veth27 scope link
  ip route add default dev ens192
  "

set +x

echo "export pid_netns1=$pid_netns1"
echo "export pid_netns2=$pid_netns2"
echo "export pid_netns3=$pid_netns3"
echo "export pid_netns4=$pid_netns4"
echo "export pid_netns5=$pid_netns5"
echo "export pid_netns6=$pid_netns6"
echo "export pid_netns7=$pid_netns7"

