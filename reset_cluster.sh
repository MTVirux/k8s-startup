#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run with sudo."
    exit 1
fi


function prep_env_vars () {

    # Check if the .env file exists
    if [ -f .env ]; then

        sudo apt-get update
        sudo apt-get install dos2unix -y

        #Remove possible return carriages from Github CRLF settings 
        dos2unix .env | tee $MASTER_LOG

        # Read the .env file, remove comments and export variables
        export $(grep -v '^#' .env | sed -e 's/#.*//' -e '/^WORKER_NODE_IPS_TO_CLUSTER=/ s/ //g' | xargs)

        # Separate the WORKER_NODE_IPS_TO_CLUSTER by comma and print each IP
        IFS=',' read -ra IP_LIST <<< "$WORKER_NODE_IPS_TO_CLUSTER"
        for IP in "${IP_LIST[@]}"; do
            echo "WORKER_IP_FOUND: $IP" | tee $MASTER_LOG
        done

    else
        echo "ERROR: .env file not found." | tee $MASTER_LOG
        exit 1
    fi

}

function prep_ssh () {

    SSH_SECURITY_OPTIONS=""

    if [ "$SSH_USER" = "" ]; then

        echo "ERROR: EMPTY SSH_USER" | tee $MASTER_LOG

    fi

    if [ -f "$SSH_IDENTITY_FILE" ]; then
        echo "SSH identity file found..." | tee $MASTER_LOG
        SSH_SECURITY_OPTIONS="-i$SSH_IDENTITY_FILE"
    else
        echo "ERROR: $SSH_IDENTITY_FILE (SSH identity file) not found" | tee $MASTER_LOG
        exit 1
    fi

}

prep_env_vars
prep_ssh


echo "Resetting master"

if [ $PREP_MASTER = true ]; then
    #Remove k8s
    sudo kubeadm reset -f
    sudo apt purge kubeadm kubelet kubectl kubernetes-cni -y
    
    #Remove helm
    sudo helm delete 
    sudo helm delete kubernetes-dashboard --namespace kubernetes-dashboard
    sudo snap remove helm

    if [ $UNINSTALL_SNAP_ON_RESET = true ]; then
        sudo apt purge snap -y
    fi
    
    if [ $UNINSTALL_K8S_ON_RESET = true ]; then
        sudo apt purge kubeadm kubelet kubectl kubernetes-cni -y
    fi

    if [ $RUN_APT_AUTOREMOVE_ON_RESET =  true ]; then
        sudo apt autoremove -y
    fi

    rm -f $HOME/.kube/config

fi

for IP in "${IP_LIST[@]}"
do
    echo "Resetting worker $@"

    if [ $IGNORE_SSH_FINGERPRINT_CHANGE = true ]; then
        ssh-keygen -R $IP 
        ssh-keyscan -H $IP >> /root/.ssh/known_hosts
    fi

    ssh $SSH_SECURITY_OPTIONS "$SSH_USER@$IP" "sudo kubeadm reset -f"
    
    if [ $UNINSTALL_K8S_ON_RESET = true ]; then
        sudo apt purge kubeadm kubelet kubectl kubernetes-cni -y && sudo apt autoremove
    fi
done