#!/bin/bash
set -e

# 1. Evita que o Ubuntu abra janelas interativas durante o apt upgrade
export DEBIAN_FRONTEND=noninteractive

# Log everything to a file
exec > >(tee /var/log/cloud-init-output.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "--- Starting Cloud-Init Script ---"

echo "--- Forcing apt to use IPv4 ---"
echo 'Acquire::ForceIPv4 "true";' | tee /etc/apt/apt.conf.d/99force-ipv4

# Manually set a public DNS server as a fallback for this script's session.
# This is a powerful debugging step to bypass potential VCN DNS issues.
echo "--- Temporarily setting public DNS ---"
echo "nameserver 8.8.8.8" | tee /etc/resolv.conf > /dev/null

# Wait for network and DNS to be ready. This prevents failures on initial boot.
echo "--- Waiting for network and DNS resolution ---"
until ping -c 1 google.com &>/dev/null; do
    echo "Network not ready, waiting 5 seconds..."
    sleep 5
done
echo "--- Network and DNS are up ---"

# 2. Update e Upgrade com flags que forçam o uso das configurações atuais (sem travar)
apt-get update
apt-get upgrade -y -o Dpkg::Options::="--force-confold"

# 3. Instalação de ferramentas básicas
apt-get install -y apt-transport-https ca-certificates curl software-properties-common git


# --- Create and enable a 2GB swap file ---
echo "Creating 2GB swap file..."
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
# Make the swap file permanent
echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
echo "Swap file created and enabled."

# --- Restante do seu script de Docker ---
echo "--- Running network diagnostics before Docker install ---"
echo "--- Testing connection to download.docker.com:443 with verbose output ---"
curl -v https://download.docker.com
echo "--- Diagnostics finished. The command above should show the connection attempt. ---"

echo "--- Installing Docker ---"
# Use /etc/apt/keyrings (padrão moderno do Docker) para evitar avisos de segurança
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# Add ubuntu user to docker group
usermod -aG docker ubuntu


# 3. Install Docker Compose v2
echo "--- Installing Docker Compose ---"
DOCKER_COMPOSE_VERSION="v2.24.6" # Use a specific version for stability. The $$ below escapes the variable for the terraform templatefile function.
# Re-apply public DNS fix. The network stack can sometimes be reset after installing packages like Docker.
echo "--- Re-applying public DNS before curl ---"
echo "nameserver 8.8.8.8" | tee /etc/resolv.conf > /dev/null

mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL --retry 3 --retry-delay 5 "https://github.com/docker/compose/releases/download/$${DOCKER_COMPOSE_VERSION}/docker-compose-linux-$(uname -m)" -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Verify installations
docker --version
docker compose version

# 4. Setup Application Directory
echo "--- Setting up application directory ---"
APP_DIR="/opt/saas-platform"

mkdir -p $${APP_DIR}
chown -R ubuntu:ubuntu $${APP_DIR}

# We will clone the repo as the 'ubuntu' user during the first deploy
# For now, the directory is ready.

# 5. Enable Docker, clone repo, and start services
systemctl enable docker

# Clone the repository as the 'ubuntu' user. The REPO_URL is passed by Terraform.
if [ ! -d "$$APP_DIR/.git" ]; then
  echo "Cloning repository..."
  sudo -u ubuntu git clone ${REPO_URL} $${APP_DIR}
fi

if [ -f "$${APP_DIR}/deploy/${compose_file}" ]; then
  echo "Starting services from ${compose_file}..."
  cd $${APP_DIR}/deploy
  # Create a dummy .env file if it doesn't exist, so compose doesn't fail
  touch .env
  docker compose -f ${compose_file} up -d --build
else
  echo "Failed to find compose file: $${APP_DIR}/deploy/${compose_file}"
fi

echo "--- Cloud-Init Script Finished Successfully ---"

# The deployment itself (cloning the repo and running docker compose)
# will be handled by the GitHub Actions pipeline.

# --- 6. Healthcheck ---
echo "--- Running Healthcheck ---"

# Verifica se o Docker está respondendo
if docker ps > /dev/null 2>&1; then
    echo "✅ Docker: OK"
else
    echo "❌ Docker: FAILED"
    exit 1
fi

# Verifica se o Compose está instalado
if docker compose version > /dev/null 2>&1; then
    echo "✅ Docker Compose: OK"
else
    echo "❌ Docker Compose: FAILED"
    exit 1
fi

# Cria um marcador de sucesso para o seu pipeline saber que acabou
touch /var/log/cloud-init-done

echo "--- Cloud-Init Script Finished Successfully at $(date) ---"