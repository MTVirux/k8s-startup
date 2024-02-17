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
sudo snap install helm --classic 

#
# Prep containerd config
#

sudo rm -f /etc/containerd/config.toml
sudo mkdir -p /etc/containerd && sudo touch /etc/containerd/config.toml
sudo /usr/bin/containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = .*/SystemdCgroup = true/' /etc/containerd/config.toml
sed -i 's/sandbox_image = .*/sandbox_image = "registry.k8s.io\/pause:3.9"/' /etc/containerd/config.toml

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

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update

#
# Install K8S and its components
#

sudo apt-get install kubeadm kubelet kubectl kubernetes-cni -y

strace -eopenat kubectl version