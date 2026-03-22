#!/bin/bash
# =============================================================================
# collect_metrics.sh - Collect Kubernetes resource metrics during an experiment
# SENG 533 - Group 25
#
# Run this in a background process while run_benchmark.sh is executing.
#
# Usage: ./collect_metrics.sh <output_file> [interval_seconds]
#   output_file:      where to write metrics (CSV)
#   interval_seconds: polling interval (default: 2)
#
# Example:
#   ./collect_metrics.sh ../results/cpu_0.5/set/c50_k8s_metrics.csv 2 &
#   METRICS_PID=$!
#   ./run_benchmark.sh 0.5 set 50 ../results/cpu_0.5/set
#   kill $METRICS_PID
# =============================================================================

OUTPUT_FILE="${1:-/tmp/k8s_metrics.csv}"
INTERVAL="${2:-2}"
CPU_LIMIT="${3:-}"   # e.g. 0.25 | 0.5 | 1.0 — used to compute CPU utilization %

mkdir -p "$(dirname "$OUTPUT_FILE")"

# Write CSV header
echo "timestamp,pod_name,cpu_cores_used,cpu_pct,memory_mb_used" > "$OUTPUT_FILE"

echo "[collect_metrics] Collecting metrics every ${INTERVAL}s → $OUTPUT_FILE"
echo "[collect_metrics] Stop with: kill $$"

while true; do
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # kubectl top pod returns lines like:
    #   NAME                     CPU(cores)   MEMORY(bytes)
    #   redis-7d9f8b6c4d-xkqvp   3m           12Mi
    kubectl top pod -l app=redis --no-headers 2>/dev/null | while read -r POD CPU MEM; do
        # Strip units: "3m" -> 0.003 cores, "12Mi" -> 12 MB
        CPU_VAL=$(echo "$CPU" | sed 's/m//' | awk '{printf "%.4f", $1/1000}')
        MEM_VAL=$(echo "$MEM" | sed 's/Mi//' | sed 's/Gi//' | awk '{print $1}')

        # Compute CPU utilization % relative to the pod's CPU limit
        if [ -n "$CPU_LIMIT" ] && [ "$CPU_LIMIT" != "0" ]; then
            CPU_PCT=$(awk "BEGIN {printf \"%.2f\", $CPU_VAL / $CPU_LIMIT * 100}")
        else
            CPU_PCT="N/A"
        fi

        echo "$TIMESTAMP,$POD,$CPU_VAL,$CPU_PCT,$MEM_VAL" >> "$OUTPUT_FILE"
    done

    sleep "$INTERVAL"
done
