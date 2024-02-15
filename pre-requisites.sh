#!/bin/bash

#
# DISABLE SWAP
#

#Disable swap to allow kubelet to function properly
sudo swapoff -a

# Copy original fstab to backup file
sudo cp "$fstab_path" "$backup_file"

# Comment out the swap entry in the fstab file
sudo awk '!/^#/ && /swap/ {$0="#"$0} {print}' "$fstab_path" > "$temp_file"

# Replace the original fstab with the modified one
sudo mv "$temp_file" "$fstab_path"



#
# Install dependencies
#

sudo apt-get install docker.io apt-transport-https curl -y

#
# Add k8s keys
#

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update

#
# Install K8S and its components
#

sudo apt-get install kubeadm kubelet kubectl kubernetes-cni -y