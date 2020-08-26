#
# simple host-to-host ipip tunnel
#
# set up 3 namespaces with diff hostnames

set -x

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

set +x

echo "export pid_netns1=$pid_netns1"
echo "export pid_netns2=$pid_netns2"
echo "export pid_netns3=$pid_netns3"
echo "export pid_netns4=$pid_netns4"
echo "export pid_netns5=$pid_netns5"
echo "export pid_netns6=$pid_netns6"
echo "export pid_netns7=$pid_netns7"

