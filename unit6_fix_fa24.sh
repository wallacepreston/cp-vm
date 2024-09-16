#!/bin/bash
red='\033[0;31m'
green='\033[0;32m'
none='\033[0m'
yellow='\033[1;33m'
bold='\033[1m'

##########################################
############### REFERENCES ###############
##
## CATALYST LOCAL INSTALL:
##  https://catalyst-soar.com/docs/catalyst/admin/install/#local-installation
##
## DOCKER COMPOSE STANDALONE 
##  https://docs.docker.com/compose/install/standalone/
##
## DOCKER 
##  https://github.com/fmidev/smartmet-server/blob/master/docs/Setting-up-Docker-and-Docker-Compose-(Ubuntu-16.04-and-18.04.1).md
##
## Script developed by rollingcoconut and sarcb 
##########################################

echo "[UNIT 6 LAB/PROJECT SPRING 2024 FIX] Starting script..."

# Check if the user is root
if [ "$EUID" -ne 0 ]; then
    echo -e "${red}[ERROR]${none} Please run using sudo."
    exit 1
fi

# Add Docker's official GPG key from the Ubuntu keyserver
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 7EA0A9C3F273FCD8

# Installing dependencies: curl and unzip to ensure system won't crash
if ! dpkg -s curl > /dev/null; then
    echo -e "${red}[CURL]${none} Curl not installed. Installing now..."
    apt update && apt install curl -y
    echo -e "${green}[CURL]${none} Curl installed."
fi

if ! dpkg -s unzip > /dev/null; then
    echo -e "${red}[UNZIP]${none} Unzip not installed. Installing now..."
    apt install unzip -y
    echo -e "${green}[UNZIP]${none} Unzip installed."
fi

CATALYST_INSTALL_PATH=/opt/catalyst
mkdir -p $CATALYST_INSTALL_PATH
pushd $CATALYST_INSTALL_PATH

#### CATALYST LOCAL INSTALL: UPDATE /ETC/HOSTS
if ! grep -q "catalyst.localhost" /etc/hosts; then
    echo "127.0.0.1 catalyst.localhost" | sudo tee -a /etc/hosts
    echo "127.0.0.1 authelia.localhost" | sudo tee -a /etc/hosts
fi

#### DOCKER-COMPOSE INSTALL
DOCKER_COMPOSE_INSTALLED=$(docker-compose --version)
if [[ "$DOCKER_COMPOSE_INSTALLED" =~ "Docker Compose version" ]]; then
    echo -e "${green}[DOCKER-COMPOSE SETUP]${none} docker-compose is already installed."
else
    echo -e "${yellow}[DOCKER-COMPOSE SETUP]${none} INSTALLING DOCKER-COMPOSE"
    
    # Detect system architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.6/docker-compose-linux-x86_64"
    elif [[ "$ARCH" == "aarch64" ]]; then
        COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.6/docker-compose-linux-aarch64"
    else
        echo -e "${red}[DOCKER-COMPOSE SETUP]${none} Unsupported architecture: $ARCH"
        exit 1
    fi
    
    # Remove any existing incorrect Docker Compose binary
    sudo rm -f /usr/local/bin/docker-compose
    sudo rm -f /usr/bin/docker-compose
    
    # Download and install Docker Compose
    sudo curl -SL $COMPOSE_URL -o /usr/local/bin/docker-compose
    sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    
    # Create symbolic link if it doesn't exist
    if [ ! -L /usr/bin/docker-compose ]; then
        sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
    fi
fi

#### CATALYST LOCAL INSTALL: DOCKER
DOCKER_ACTIVE=$(systemctl is-active docker)
if [[ "$DOCKER_ACTIVE" == "active" ]]; then
    echo -e "${green}[DOCKER SETUP]${none} Docker is already installed."
else
    echo -e "${yellow}[DOCKER SETUP]${none} INSTALLING DOCKER"

    # Ensure the docker group exists
    if ! getent group docker > /dev/null; then
        echo -e "${yellow}[INFO]${none} Docker group does not exist. Creating docker group..."
        sudo groupadd docker
    fi
    
    # Check if the user is in the docker group
    if ! groups $USER | grep -q '\bdocker\b'; then
        echo -e "${red}[ERROR]${none} User is not in the docker group. Adding user to docker group..."
        sudo usermod -aG docker $USER
        echo -e "${yellow}[INFO]${none} Applying group membership changes..."
        echo -e "${yellow}[INFO]${none} Please restart terminal session and re-run this script for the changes to take effect."
        exec newgrp docker
    fi

    # Remove any existing Docker repository entries
    sudo rm -f /etc/apt/sources.list.d/docker.list
    sudo rm -f /etc/apt/trusted.gpg.d/docker.asc

    # Download the Docker GPG key and move it to trusted keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/trusted.gpg.d/docker.asc

    # Detect system architecture
    ARCH=$(dpkg --print-architecture)
    if [[ "$ARCH" == "amd64" ]]; then
        REPO_URL="https://download.docker.com/linux/ubuntu"
    elif [[ "$ARCH" == "arm64" ]]; then
        REPO_URL="https://download.docker.com/linux/ubuntu"
    else
        echo -e "${red}[DOCKER SETUP]${none} Unsupported architecture: $ARCH"
        exit 1
    fi

    # Add the Docker repository
    echo "deb [arch=$ARCH] $REPO_URL $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list

    # Update and install Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io

    # Create the docker group if it doesn't exist
    if ! getent group docker > /dev/null; then
        sudo groupadd docker
    fi

    # Add the current user to the docker group
    sudo usermod -aG docker ${USER}
fi

#### Check if apache2 is running
APACHE2_ACTIVE=$(systemctl is-active apache2)
if [[ "$APACHE2_ACTIVE" == "active" ]]; then
    echo -e "${yellow}[APACHE2]${none} DISABLING APACHE2"
    sudo service apache2 stop
    sudo systemctl disable apache2
else
    echo -e "${green}[APACHE2]${none} Apache2 is already disabled."
fi

#### Check if nginx is running
NGINX_ACTIVE=$(systemctl is-active nginx)
if [[ "$NGINX_ACTIVE" == "active" ]]; then
    echo -e "${yellow}[NGINX]${none} Stopping NGINX"
    sudo service nginx stop
else
    echo -e "${green}[NGINX]${none} Nginx is already stopped."
fi

#### CATALYST LOCAL INSTALL: CATALYST
CATALYST_INSTALLED=$(docker compose ls -q --filter name=catalyst-setup-sp24-main)
if [ -n "$CATALYST_INSTALLED" ]; then
    echo -e "${green}[CATALYST SETUP]${none} Catalyst is already running.  Try connecting at https://catalyst.localhost"
    echo -e "\nTo ${red}stop${none} it, use the following command:"
    echo -e "\n  ${bold}docker compose -f /opt/catalyst/catalyst-setup-sp24-main/docker-compose.yml down${none}\n"
    echo -e "To ${yellow}restart${none} it, use the following command:"
    echo -e "\n  ${bold}docker compose -f /opt/catalyst/catalyst-setup-sp24-main/docker-compose.yml up --detach${none}\n"
    exit 0
else
    # verify that this is the first install to prevent arangodb root password issues
    if [ -n "$(docker volume ls -q --filter name=catalyst-setup-sp24-main_arangodb)" ]; then
        echo -e "${yellow}[CATALYST SETUP]${none} Catalyst seems to already be installed, but is not currently running."
        echo -e "\nTo ${green}start${none} it, use the following command:"
        echo -e "\n  ${bold}docker compose -f /opt/catalyst/catalyst-setup-sp24-main/docker-compose.yml up --detach${none}\n"
        echo -e "To ${red}stop${none} it, use the following command:"
        echo -e "\n  ${bold}docker compose -f /opt/catalyst/catalyst-setup-sp24-main/docker-compose.yml down${none}\n"
        exit 1
    else
        echo -e "${yellow}[CATALYST SETUP]${none} INSTALLING CATALYST"
        curl -sL https://raw.githubusercontent.com/sarcb/catalyst-setup-sp24/main/install_catalyst.sh -o install_catalyst.sh
        openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes -keyout example.key -out example.crt -subj "/CN=localhost"
        sudo bash install_catalyst.sh https://catalyst.localhost https://authelia.localhost $CATALYST_INSTALL_PATH/example.crt $CATALYST_INSTALL_PATH/example.key admin:admin:admin@example.com
    fi
fi

#### VERIFY
CATALYST_INSTALLED=$(docker compose ls -q --filter name=catalyst-setup-sp24-main)
if [ -n "$CATALYST_INSTALLED" ]; then
    echo -e "${green}[CATALYST SETUP]${none} Catalyst is running.  Try connecting at https://catalyst.localhost"
else
    echo -e "${red}[CATALYST SETUP]${none} Catalyst is not running.  Please check the logs for errors."
fi

### CLEANUP 
if [[ $PWD != $CATALYST_INSTALL_PATH  ]]; then 
    popd
fi
