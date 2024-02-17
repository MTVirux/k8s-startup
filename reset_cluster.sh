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
        TOTAL_NUMBER_OF_WORKERS = 0 #Filled below from parsing IP_LIST
        CURRENT_ACTIVE_WORKER = -1
        IFS=',' read -ra IP_LIST <<< "$WORKER_NODE_IPS_TO_CLUSTER"
        for IP in "${IP_LIST[@]}"; do
            echo "WORKER_IP_FOUND: $IP" | tee $MASTER_LOG
            $TOTAL_NUMBER_OF_WORKERS=$TOTAL_NUMBER_OF_WORKERS + 1
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



if [ $PREP_MASTER = true ]; then

    echo "Resetting master..."

    #Remove k8s
    sudo kubeadm reset -f
    sudo kubectl delete all --all-namespaces --all
    
    #Remove helm
    sudo helm delete 
    sudo helm delete kubernetes-dashboard --namespace kubernetes-dashboard
    sudo snap remove helm

    if [ $UNINSTALL_SNAP_ON_RESET = true ]; then
        sudo apt purge snap -y
    fi
    
    if [ $UNINSTALL_K8S_ON_RESET = true ]; then
        sudo apt-get purge kubeadm kubectl kubelet kubernetes-cni kube*   
    fi

    if [ $RUN_APT_AUTOREMOVE_ON_RESET =  true ]; then
        sudo apt autoremove -y
    fi

    #Delete configs and data
    sudo rm -rf ~/.kube
    sudo rm -rf /etc/cni
    sudo rm -rf /etc/kubernetes
    sudo rm -rf /var/lib/etcd
    sudo rm -rf /var/lib/kubelet

    #Reset iptables
    sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X

fi

for IP in "${IP_LIST[@]}"
do
    $CURRENT_ACTIVE_WORKER=$CURRENT_ACTIVE_WORKER + 1

    echo "Resetting worker $CURRENT_ACTIVE_WORKER"

    if [ $IGNORE_SSH_FINGERPRINT_CHANGE = true ]; then
        ssh-keygen -R $IP 
        ssh-keyscan -H $IP >> /root/.ssh/known_hosts
    fi

    ssh $SSH_SECURITY_OPTIONS "$SSH_USER@$IP" "sudo kubeadm reset -f"
    
    if [ $UNINSTALL_K8S_ON_RESET = true ]; then
        sudo apt purge kubeadm kubelet kubectl kubernetes-cni -y && sudo apt autoremove
    fi

done