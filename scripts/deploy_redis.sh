#!/bin/bash
# =============================================================================
# deploy_redis.sh - Deploy Redis with a specific CPU limit
# SENG 533 - Group 25
#
# Usage: ./deploy_redis.sh <cpu_limit>
#   cpu_limit: 0.25 | 0.5 | 1.0
#
# Example: ./deploy_redis.sh 0.5
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

CPU_LIMIT="${1:-}"

if [ -z "$CPU_LIMIT" ]; then
    log_error "Usage: $0 <cpu_limit>  (valid values: 0.25 | 0.5 | 1.0)"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$SCRIPT_DIR/../k8s"

# Map cpu argument to deployment file
case "$CPU_LIMIT" in
    0.25) DEPLOY_FILE="$K8S_DIR/redis-deployment-0.25cpu.yaml" ;;
    0.5)  DEPLOY_FILE="$K8S_DIR/redis-deployment-0.5cpu.yaml"  ;;
    1.0|1)  DEPLOY_FILE="$K8S_DIR/redis-deployment-1cpu.yaml"  ;;
    *)
        log_error "Invalid CPU limit: $CPU_LIMIT. Valid values: 0.25 | 0.5 | 1.0"
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# 1. Delete existing Redis deployment if any
# ---------------------------------------------------------------------------
if kubectl get deployment redis &>/dev/null; then
    log_info "Removing existing Redis deployment..."
    kubectl delete deployment redis --grace-period=5
    # Wait until the old pod is gone
    log_info "Waiting for old Redis pod to terminate..."
    kubectl wait --for=delete pod -l app=redis --timeout=60s 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 2. Apply new deployment
# ---------------------------------------------------------------------------
log_info "Deploying Redis with CPU limit: $CPU_LIMIT cores..."
kubectl apply -f "$DEPLOY_FILE"

# ---------------------------------------------------------------------------
# 3. Wait for pod to be Ready
# ---------------------------------------------------------------------------
log_info "Waiting for Redis pod to be ready (up to 120s)..."
kubectl rollout status deployment/redis --timeout=120s

POD_NAME=$(kubectl get pods -l app=redis -o jsonpath='{.items[0].metadata.name}')
log_info "Redis pod ready: $POD_NAME"

# ---------------------------------------------------------------------------
# 4. Start port-forwarding in background
# ---------------------------------------------------------------------------
# Kill any existing port-forward for 6379
pkill -f "kubectl port-forward.*6379" 2>/dev/null || true
sleep 1

log_info "Starting port-forwarding on 127.0.0.1:6379..."
kubectl port-forward service/redis-service 6379:6379 &>/tmp/port-forward.log &
PF_PID=$!
echo "$PF_PID" > /tmp/redis-portforward.pid

# Brief wait to confirm port-forward is up
sleep 3

# Validate connection
if redis-cli -h 127.0.0.1 -p 6379 ping | grep -q PONG; then
    log_info "Redis is reachable at 127.0.0.1:6379 (PONG received)"
else
    log_error "Redis did not respond to PING. Check port-forwarding logs at /tmp/port-forward.log"
    exit 1
fi

log_info "Redis deployed and ready (CPU limit: $CPU_LIMIT cores)."
