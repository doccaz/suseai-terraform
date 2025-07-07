#!/bin/bash
set -e -x

# --- Fail immediately if credentials are not set ---
# These variables are passed in from the Terraform template
if [ -z "${scc_username}" ] || [ -z "${scc_token}" ] || [ -z "${suse_registration_code}" ]; then
  echo "Error: SCC_USERNAME, SCC_TOKEN, and SUSE_REGISTRATION_CODE must be set." >&2
  exit 1
fi

# --- Determine Hostnames ---
if [ -z "${rancher_hostname}" ]; then
  echo "Error: rancher_hostname must be set." >&2
  exit 1
fi
if [ -z "${open_webui_hostname}" ]; then
  echo "Error: open_webui_hostname must be set." >&2
  exit 1
fi

# --- System Registration and Prerequisite Installation ---
echo "Registering the system with SUSE Customer Center..."
# Register the base system.
SUSEConnect -r "${suse_registration_code}"

echo "Installing native NVIDIA GPU driver binaries (G06)..."
zypper addrepo --refresh 'https://developer.download.nvidia.com/compute/cuda/repos/sles15/x86_64/cuda-sles15.repo'
zypper --gpg-auto-import-keys refresh
# Install only the necessary driver components (kernel module and compute libraries), not the full CUDA toolkit.
zypper install -y --auto-agree-with-licenses nvidia-compute-G06 nvidia-compute-utils-G06 curl jq

# --- Install RKE2 for a single-node Kubernetes cluster ---
echo "Installing RKE2..."
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="server" sh -
systemctl enable --now rke2-server.service

# --- Wait for RKE2 to be ready by checking for the kubeconfig file ---
echo "Waiting for RKE2 to be ready..."
TIMEOUT=300 # 5 minutes
COUNTER=0
while [ ! -f /etc/rancher/rke2/rke2.yaml ]; do
  if [ $COUNTER -ge $TIMEOUT ]; then
    echo "Timed out waiting for RKE2 to start."
    exit 1
  fi
  sleep 10
  COUNTER=$((COUNTER + 10))
done
echo "RKE2 is ready."

# --- Configure kubectl ---
# Add RKE2 binaries to the path for this script's session
export PATH=$PATH:/var/lib/rancher/rke2/bin
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
mkdir -p /root/.kube
cp /etc/rancher/rke2/rke2.yaml /root/.kube/config
chmod 600 /root/.kube/config

# Ensure kubectl is in the standard path for other tools like Helm
ln -s /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl

# --- Install Helm ---
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# --- Login to the SUSE OCI Registry for cert-manager and SUSE AI ---
echo "Logging into SUSE OCI Registry..."
helm registry login dp.apps.rancher.io/charts -u "${scc_username}" -p "${scc_token}"

# --- Add public Helm repositories ---
echo "Adding Helm repositories..."
helm repo add rancher-prime https://charts.rancher.com/server-charts/prime
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# --- Create Namespaces ---
kubectl create namespace cattle-system
kubectl create namespace cert-manager
kubectl create namespace suse-ai
kubectl create namespace gpu-operator

# --- Create Registry Secret for Kubernetes (for cert-manager and suse-ai) ---
# This allows Kubernetes to pull images from the authenticated registry
kubectl create secret docker-registry application-collection \
  --docker-server=dp.apps.rancher.io \
  --docker-username="${scc_username}" \
  --docker-password="${scc_token}" \
  -n cert-manager

kubectl create secret docker-registry application-collection \
  --docker-server=dp.apps.rancher.io \
  --docker-username="${scc_username}" \
  --docker-password="${scc_token}" \
  -n suse-ai

# --- NVIDIA GPU Operator Installation and Configuration ---
echo "Configuring and installing NVIDIA GPU Operator..."

# 1. Label the node to indicate it has a GPU
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl label nodes $NODE_NAME nvidia.com/gpu=present --overwrite

# 2. Create the time-slicing configuration as a ConfigMap
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-slicing-config
  namespace: gpu-operator
data:
  config.yaml: |
    version: v1
    sharing:
      timeSlicing:
        resources:
        - name: nvidia.com/gpu
          replicas: 4
EOF

# 3. Install the GPU Operator, instructing it to use the pre-installed native driver and enabling the toolkit
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --set driver.enabled=false \
  --set toolkit.enabled=true \
  --set devicePlugin.config.name=time-slicing-config

echo "Waiting for NVIDIA GPU Operator to be ready..."
kubectl wait --for=condition=Available deployment --all -n gpu-operator --timeout=600s


# --- Install cert-manager from Application Collection ---
# Required dependency for Rancher
echo "Installing cert-manager..."
helm install cert-manager oci://dp.apps.rancher.io/charts/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --set global.imagePullSecrets[0].name=application-collection

echo "Waiting for cert-manager to be ready..."
kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=300s

# --- Install Rancher Prime from Public Helm Repository ---
echo "Installing Rancher Prime..."
helm install rancher rancher-prime/rancher \
  --namespace cattle-system \
  --create-namespace \
  --set hostname=${rancher_hostname} \
  --set bootstrapPassword=admin

echo "Waiting for Rancher to be fully deployed..."
kubectl -n cattle-system wait --for=condition=Available deployment/rancher --timeout=600s

# --- Install SUSE AI Deployer from Application Collection with GPU enabled ---
# This chart will install NeuVector Prime, Longhorn, and Grafana as dependencies
echo "Installing SUSE AI Deployer with GPU enabled..."
helm install suse-ai-deployer oci://dp.apps.rancher.io/charts/suse-ai-deployer \
  --namespace suse-ai \
  --create-namespace \
  --set global.imagePullSecrets[0].name=application-collection \
  --set ollama.gpu.enabled=true \
  --set ollama.nodeSelector."nvidia\.com/gpu"=present \
  --set ollama.resources.limits."nvidia\.com/gpu"=1 \
  --set open-webui.ingress.host=${open_webui_hostname} \
  --set open-webui.tls[0].hosts[0]=${open_webui_hostname}

echo "SUSE AI deployment initiated. It may take several minutes for all components to become active."
echo "Access Rancher at: https://${rancher_hostname}"
echo "Access Open WebUI at: https://${open_webui_hostname}"
echo "Bootstrap password is: admin"
