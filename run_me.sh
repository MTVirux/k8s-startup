#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run with sudo."
    exit 1
fi

function pre_reqs () {

    ./pre_requisites.sh

}


function setup_workers () {

    TARGET_IP=$1
    WORKER_ID=$2

    if [ $IGNORE_SSH_FINGERPRINT_CHANGE = true ]; then
        ssh-keygen -R $TARGET_IP 
        ssh-keyscan -H $TARGET_IP >> /root/.ssh/known_hosts
    fi

    sudo ssh "$SSH_SECURITY_OPTIONS" "$SSH_USER@$TARGET_IP" "sudo bash -s" < "./pre_requisites.sh" | tee $WORKER_LOG_DIR/worker$2.log
    sudo ssh "$SSH_SECURITY_OPTIONS" "$SSH_USER@$TARGET_IP" "sudo $WORKER_JOIN_COMMAND" | tee $WORKER_LOG_DIR/worker@.log

}

function setup_master () {

    #
    # Start kubeadm
    #

    echo "Running kubeadm init..." | tee $MASTER_LOG $KUBEADM_INIT_LOG
    sudo kubeadm init > $KUBEADM_INIT_LOG
    WORKER_JOIN_COMMAND=$(grep -zo "kubeadm join.*" "$KUBEADM_INIT_LOG" | tr -d '\n' | tr -d '\\' | sed 's/ \{2,\}/ /g')

   
    # Check if WORKER_JOIN_COMMAND was found
    if [ -z "$WORKER_JOIN_COMMAND" ]; then
        echo "Error: WORKER_JOIN_COMMAND not found. Exiting script." | tee $MASTER_LOG
        exit 1
    fi

    echo "\n\n - Using the following kubeadm join command: $WORKER_JOIN_COMMAND" | tee $MASTER_LOG
    
    # Fix config by copying the admin.conf from kubernetes
    echo "\n Fixing config..." | tee $MASTER_LOG
    mkdir -p $HOME/.kube
    sudo rm -f $HOME.kube/config
    sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
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

function prep_logs () {

    TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
    mkdir -p ./logs/"$TIMESTAMP"/
    MASTER_LOG=./logs/"$TIMESTAMP"/master.log
    WORKER_LOG_DIR=./logs/"$TIMESTAMP"/
    KUBEADM_INIT_LOG=./logs/"$TIMESTAMP"/kubeadm_init.log

}

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

function deploy_dashboard ()  {

    sudo helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
    helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace kubernetes-dashboard

}


function main () {

    if [ $PREP_MASTER ]; then
        echo "********* PREPPING MASTER *********" | tee $MASTER_LOG
        echo "Running pre-requisites on master..." | tee $MASTER_LOG
        chmod +x ./pre_requisites.sh
        ./pre_requisites.sh
        setup_master
    fi

    for IP in "${IP_LIST[@]}"
    do
        echo "********* PREPPING WORKER $@ *********" | tee $MASTER_LOG
        setup_workers $IP $@
    done

}


prep_logs
prep_env_vars
prep_ssh
main
deploy_dashboard




