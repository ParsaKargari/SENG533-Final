#!/bin/bash
# =============================================================================
# run_benchmark.sh - Run a single redis-benchmark experiment
# SENG 533 - Group 25
#
# Usage: ./run_benchmark.sh <cpu_limit> <workload> <clients> <output_dir>
#   cpu_limit:  0.25 | 0.5 | 1.0
#   workload:   set | get
#   clients:    number of concurrent clients (e.g., 1, 10, 50, 100, 200)
#   output_dir: directory to write results into
#
# Example: ./run_benchmark.sh 0.5 set 50 ../results/cpu_0.5/set
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
WORKLOAD="${2:-}"
CLIENTS="${3:-}"
OUTPUT_DIR="${4:-}"

# Validate args
if [ -z "$CPU_LIMIT" ] || [ -z "$WORKLOAD" ] || [ -z "$CLIENTS" ] || [ -z "$OUTPUT_DIR" ]; then
    log_error "Usage: $0 <cpu_limit> <workload> <clients> <output_dir>"
    exit 1
fi

if [[ "$WORKLOAD" != "set" && "$WORKLOAD" != "get" ]]; then
    log_error "Workload must be 'set' or 'get'"
    exit 1
fi

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
REDIS_HOST="127.0.0.1"
REDIS_PORT=6379
PIPELINE=1           # no pipelining — matches single-request latency model
RUNS=3               # number of repeated runs per config (averaged later)
TOTAL_REQUESTS=10000 # fixed across all experiments for fair comparison

mkdir -p "$OUTPUT_DIR"

OUTPUT_FILE="$OUTPUT_DIR/c${CLIENTS}.csv"
RAW_FILE="$OUTPUT_DIR/c${CLIENTS}_raw.txt"

log_info "Running experiment: cpu=$CPU_LIMIT  workload=$WORKLOAD  clients=$CLIENTS"
log_info "Output → $OUTPUT_FILE"

# ---------------------------------------------------------------------------
# Flush any existing data so GET tests don't fail on missing keys
# ---------------------------------------------------------------------------
if [ "$WORKLOAD" = "get" ]; then
    log_info "Pre-populating keys for GET workload..."
    redis-benchmark -h "$REDIS_HOST" -p "$REDIS_PORT" \
        -t set -c 50 -n "$TOTAL_REQUESTS" -q > /dev/null 2>&1
fi

# ---------------------------------------------------------------------------
# Run benchmark RUNS times and collect raw output
# ---------------------------------------------------------------------------
echo "cpu_limit,workload,clients,run,throughput_rps,avg_latency_ms,p50_latency_ms,p95_latency_ms,p99_latency_ms" > "$OUTPUT_FILE"

for run in $(seq 1 $RUNS); do
    log_info "  Run $run/$RUNS..."

    # Full verbose output captured to raw file
    RAW_RUN_FILE="${OUTPUT_DIR}/c${CLIENTS}_run${run}_raw.txt"

    redis-benchmark \
        -h "$REDIS_HOST" \
        -p "$REDIS_PORT" \
        -t "$WORKLOAD" \
        -c "$CLIENTS" \
        -n "$TOTAL_REQUESTS" \
        -P "$PIPELINE" \
        2>&1 | tee -a "$RAW_FILE" > "$RAW_RUN_FILE"

    # -------------------------------------------------------------------
    # Parse throughput and latency from redis-benchmark output
    # redis-benchmark reports:
    #   "throughput summary: XXXXX requests per second"
    #   "latency summary (msec):"
    #       "          avg       min       p50       p95       p99       max"
    #       "      X.XXX     X.XXX     X.XXX     X.XXX     X.XXX     X.XXX"
    # -------------------------------------------------------------------
    THROUGHPUT=$(grep -i "throughput summary" "$RAW_RUN_FILE" | grep -oP '[\d.]+(?= requests)' | head -1 || echo "N/A")
    LATENCY_LINE=$(grep -A2 "latency summary" "$RAW_RUN_FILE" | tail -1)
    AVG_LAT=$(echo "$LATENCY_LINE" | awk '{print $1}')
    P50_LAT=$(echo "$LATENCY_LINE" | awk '{print $3}')
    P95_LAT=$(echo "$LATENCY_LINE" | awk '{print $4}')
    P99_LAT=$(echo "$LATENCY_LINE" | awk '{print $5}')

    echo "$CPU_LIMIT,$WORKLOAD,$CLIENTS,$run,$THROUGHPUT,$AVG_LAT,$P50_LAT,$P95_LAT,$P99_LAT" >> "$OUTPUT_FILE"
    log_info "  Run $run complete: throughput=$THROUGHPUT rps, avg_lat=${AVG_LAT}ms, p95=${P95_LAT}ms, p99=${P99_LAT}ms"
done

log_info "Experiment done. Results saved to $OUTPUT_FILE"
