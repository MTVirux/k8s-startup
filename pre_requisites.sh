#!/bin/bash

#
# DISABLE SWAP
#

#Disable swap to allow kubelet to function properly
sudo swapoff -a

# Copy original fstab to backup file
sudo cp /etc/fstab /etc/fstab_backup

# Comment out the swap entry in the fstab file

sudo awk '!/^#/ && /swap/ {$0="#"$0} {print}' /etc/fstab > /etc/fstab_temp

# Replace the original fstab with the modified one
sudo mv /etc/fstab_temp /etc/fstab



#
# Install dependencies
#

sudo apt-get update
sudo apt-get install apt-transport-https curl strace snap containerd -y
#wget https://github.com/Mirantis/cri-dockerd/releases/download/v0.3.10/cri-dockerd_0.3.10.3-0.ubuntu-jammy_amd64.deb -P /tmp
#sudo dpkg -i /tmp/cri-dockerd_0.3.10.3-0.ubuntu-jammy_amd64.deb
sudo snap install helm --classic 

#
# Prep containerd config
#

# Delete previous config
sudo rm -f /etc/containerd/config.toml
# Make new config file
sudo mkdir -p /etc/containerd && sudo touch /etc/containerd/config.toml
sudo /usr/bin/containerd config default > /etc/containerd/config.toml

# Set up the mirror entry for the private registry
mirror_entry="[plugins.\"io.containerd.grpc.v1.cri\".registry.mirrors]
  [plugins.\"io.containerd.grpc.v1.cri\".registry.mirrors.\"$PRIVATE_CONTAINER_REGISTRY\"]
    endpoint = [\"$PRIVATE_CONTAINER_REGISTRY\"]"

# Setup path for the config file
config_file="/etc/containerd/config.toml"

# Modify SystemCgroup and sandbox image
sed -i 's/SystemdCgroup = .*/SystemdCgroup = true/' $config_file
sed -i 's/sandbox_image = .*/sandbox_image = "registry.k8s.io\/pause:3.9"/' $config_file


# Add the mirror entry to the config.toml file using sed
sed -i "/\[plugins\.\"io\.containerd\.grpc\.v1\.cri\"\\.registry\.mirrors\]/a $mirror_entry" $config_file


#
# CNI Config
#

#Install CNI plugins
wget https://github.com/containernetworking/plugins/releases/download/v1.4.0/cni-plugins-linux-amd64-v1.4.0.tgz -P /tmp
sudo tar Cxzvf /opt/cni/bin /tmp/cni-plugins-linux-amd64-v1.4.0.tgz 
systemctl restart containerd

#
# Forwarding IPv4 and letting iptables see bridged traffic
#

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system



#
# Add k8s repo keys
#

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update



#
# Install K8S and its components
#

sudo apt install -y kubeadm=1.29.1-1.1 kubelet=1.29.1-1.1 kubectl=1.29.1-1.1
