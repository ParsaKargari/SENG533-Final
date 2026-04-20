#!/bin/bash
# tilt_port_forward.sh — manually restart port-forward when Tilt is NOT running.
# Use this only when running scripts directly without Tilt.
# When `tilt up` is active, Tilt manages port-forwarding automatically.

pkill -f "kubectl port-forward.*6379" 2>/dev/null || true
sleep 1
kubectl port-forward service/redis-service 127.0.0.1:6379:6379 &
echo "Port-forward started (PID $!). Kill with: pkill -f 'kubectl port-forward.*6379'"
