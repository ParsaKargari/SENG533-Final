#!/bin/bash
# =============================================================================
# setup.sh - Environment Setup Script
# SENG 533 - Group 25
# Sets up Minikube, enables metrics-server, and validates the environment.
# Run this once before executing any experiments.
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ---------------------------------------------------------------------------
# 1. Prerequisite checks
# ---------------------------------------------------------------------------
log_info "Checking prerequisites..."

check_tool() {
    if ! command -v "$1" &>/dev/null; then
        log_error "$1 is not installed. Please install it and re-run this script."
        exit 1
    else
        log_info "$1 found: $(command -v $1)"
    fi
}

check_tool docker
check_tool minikube
check_tool kubectl
check_tool redis-benchmark

# ---------------------------------------------------------------------------
# 2. Start Minikube
# ---------------------------------------------------------------------------
log_info "Starting Minikube..."

MINIKUBE_STATUS=$(minikube status --format='{{.Host}}' 2>/dev/null || echo "Stopped")

if [ "$MINIKUBE_STATUS" = "Running" ]; then
    log_warn "Minikube is already running. Skipping start."
else
    minikube start --cpus=4 --memory=4096 --driver=docker
    log_info "Minikube started."
fi

# ---------------------------------------------------------------------------
# 3. Enable metrics-server addon
# ---------------------------------------------------------------------------
log_info "Enabling metrics-server addon..."
minikube addons enable metrics-server

# Wait for metrics-server to be ready
log_info "Waiting for metrics-server to be ready (up to 120s)..."
kubectl rollout status deployment/metrics-server -n kube-system --timeout=120s || \
    log_warn "metrics-server may still be starting. Continue and check manually if needed."

# ---------------------------------------------------------------------------
# 4. Apply the Redis Service (stable across all experiments)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$SCRIPT_DIR/../k8s"

log_info "Applying Redis service..."
kubectl apply -f "$K8S_DIR/redis-service.yaml"

# ---------------------------------------------------------------------------
# 5. Create results directory structure
# ---------------------------------------------------------------------------
RESULTS_DIR="$SCRIPT_DIR/../results"
for cpu in 0.25 0.5 1.0; do
    for workload in set get; do
        mkdir -p "$RESULTS_DIR/cpu_${cpu}/${workload}"
    done
done
log_info "Results directory structure created at $RESULTS_DIR"

# ---------------------------------------------------------------------------
# 6. Validate environment
# ---------------------------------------------------------------------------
log_info "Validating Minikube cluster..."
kubectl cluster-info
kubectl get nodes

log_info ""
log_info "============================================="
log_info " Setup complete! Environment is ready."
log_info " Next step: run scripts/run_all_experiments.sh"
log_info "============================================="
