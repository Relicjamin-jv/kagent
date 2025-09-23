#!/usr/bin/env bash

set -o errexit
set -o pipefail

# user selected GPU support
while true; do
  echo "1.) Nvidia \n 2.) AMD \n 3. CPU"
  read -p "Choose GPU support (1-3): " choice

  case $choice in
  1)
    nvidia-smi &>/dev/null || {
      echo "Error: Could not find Nvidia GPU, make sure drivers are installed"
      exit 1
    }
    SUPPORT="nvidia"
    break
    ;;
  2)
    if [ ! -e "/dev/kfd" ]; then
      echo "Error: AMD /dev/kfd compute interface not detected"
      exit 1
    fi
    SUPPORT="amd"
    break
    ;;
  3)
    SUPPORT="cpu"
    break
    ;;
  *)
    echo "Invalid choice."
    ;;
  esac
done

echo "Installing Ollama with $SUPPORT support."

if [ $SUPPORT = "cpu" ]; then
  docker run -d -v ollama:/root/.ollama -p 11434:11434 --name ollama ollama/ollama
fi

if [ $SUPPORT = "amd" ]; then
  docker run -d --device /dev/kfd --device /dev/dri -v ollama:/root/.ollama -p 11434:11434 --name ollama ollama/ollama:rocm
fi

if [ $SUPPORT = "nvidia" ]; then
  echo "Make sure you have NVIDIA Container Toolkit installed!"
  docker run -d --gpus=all -v ollama:/root/.ollama -p 11434:11434 --name ollama ollama/ollama
fi

docker exec -it ollama bash -c "ollama pull llama3.2:3b"

# reinstall the kagent chart with ollama defaults
KAGENT_DEFAULT_MODEL_PROVIDER="ollama" KAGENT_HELM_EXTRA_ARGS="--set providers.ollama.config.host=http://dockerhost:11434 --set providers.ollama.model=llama3.2:3b" make helm-install

# exposes host ports to kind
kubectl apply -f - <<-EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dockerhost
  namespace: kagent
  labels:
    k8s-app: dockerhost
spec:
  replicas: 1
  selector:
    matchLabels:
      k8s-app: dockerhost
  template:
    metadata:
      labels:
        k8s-app: dockerhost
    spec:
      containers:
      - name: dockerhost
        image: qoomon/docker-host
        securityContext:
          capabilities:
            add: ["NET_ADMIN", "NET_RAW"]
        env:
        # Not needed in MacOs:
        - name: DOCKER_HOST
          value: 172.17.0.1 # <-- docker bridge network default gateway
---
apiVersion: v1
kind: Service
metadata:
  name: dockerhost
  namespace: kagent
spec:
  clusterIP: None # <-- Headless service
  selector:
    k8s-app: dockerhost
EOF
