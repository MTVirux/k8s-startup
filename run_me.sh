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

    if [ $IGNORE_SSH_FINGERPRINT_CHANGE ]; then
        ssh-keygen -R $TARGET_IP 
        ssh-keyscan -H $TARGET_IP >> /root/.ssh/known_hosts
    fi

    sudo ssh "$SSH_SECURITY_OPTIONS" "$SSH_USER@$TARGET_IP" "sudo bash -s" < "./pre_requisites.sh" | tee $WORKER_LOG_DIR/worker$CURRENT_ACTIVE_WORKER.log
    sudo ssh "$SSH_SECURITY_OPTIONS" "$SSH_USER@$TARGET_IP" "sudo $WORKER_JOIN_COMMAND" | tee $WORKER_LOG_DIR/worker$CURRENT_ACTIVE_WORKER.log

}

function setup_master () {

    #
    # Start kubeadm
    #

    echo "Running kubeadm init..." | tee $MASTER_LOG $KUBEADM_INIT_LOG
    sudo kubeadm init --pod-network-cidr=$CUSTOM_POD_CIDR > $KUBEADM_INIT_LOG
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
    mkdir -p ./logs/setup-"$TIMESTAMP"/
    MASTER_LOG=./logs/setup-"$TIMESTAMP"/master.log
    WORKER_LOG_DIR=./logs/setup-"$TIMESTAMP"/
    KUBEADM_INIT_LOG=./logs/setup-"$TIMESTAMP"/kubeadm_init.log

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
        TOTAL_NUMBER_OF_WORKERS=0 #Filled below from parsing IP_LIST
        CURRENT_ACTIVE_WORKER=-1
        IFS=',' read -ra IP_LIST <<< "$WORKER_NODE_IPS_TO_CLUSTER"
        for IP in "${IP_LIST[@]}"; do
            echo "WORKER_IP_FOUND: $IP" | tee $MASTER_LOG
            ((TOTAL_NUMBER_OF_WORKERS++))
        done

        if [ $RESET_LOGS_ON_CLUSTER_SETUP ]; then
            sudo rm -rf ./logs/
        fi

    else
        echo "ERROR: .env file not found." | tee $MASTER_LOG
        exit 1
    fi

}

function deploy_dashboard ()  {

    #sudo git clone https://github.com/irsols-devops/kubernetes-dashboard.git
    #kubectl apply -f ./kubernetes-dashboard
    sudo helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    sudo helm repo update
    sudo helm install prometheus-community/kube-prometheus-stack --generate-name

}

function setup_container_networking () {

    sudo kubectl apply -f $CONTAINER_NETWORKING_ADDON

}

function post_install_monitoring () {

    sudo watch -n 1 kubectl get pods --all-namespaces

}

function setup_cert_manager () {

    sudo helm repo add jetstack https://charts.jetstack.io --force-update
    sudo helm upgrade -i -n cert-manager cert-manager-csi-driver jetstack/cert-manager-csi-driver --wait

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
        ((CURRENT_ACTIVE_WORKER++))
        echo "********* PREPPING WORKER "$CURRENT_ACTIVE_WORKER"/"$TOTAL_NUMBER_OF_WORKERS" *********" | tee $MASTER_LOG
        setup_workers $IP
    done

}


prep_logs
prep_env_vars
prep_ssh
main
setup_container_networking
setup_cert_manager
#deploy_dashboard
#post_install_monitoring