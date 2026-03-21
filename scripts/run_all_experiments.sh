#!/bin/bash
# =============================================================================
# run_all_experiments.sh - Master experiment runner
# SENG 533 - Group 25
#
# Iterates over all combinations of:
#   CPU limits   : 0.25 | 0.5 | 1.0 cores
#   Workloads    : set | get
#   Client counts: 1 | 10 | 50 | 100 | 200
#
# For each combination it:
#   1. (Re-)deploys Redis with the correct CPU limit
#   2. Starts background metrics collection
#   3. Runs redis-benchmark (3 repeated runs)
#   4. Stops metrics collection
#
# Total configurations: 3 × 2 × 5 = 30
#
# Usage: ./run_all_experiments.sh [--dry-run]
#   --dry-run  Print what would be executed without running anything
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    log_warn "DRY RUN MODE — no commands will be executed."
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/../results"
ANALYSIS_DIR="$SCRIPT_DIR/../analysis"

# ---------------------------------------------------------------------------
# Experiment matrix
# ---------------------------------------------------------------------------
CPU_LIMITS=(0.25 0.5 1.0)
WORKLOADS=(set get)
CLIENT_COUNTS=(1 10 50 100 200)

TOTAL=$(( ${#CPU_LIMITS[@]} * ${#WORKLOADS[@]} * ${#CLIENT_COUNTS[@]} ))
CURRENT=0

# ---------------------------------------------------------------------------
# Helper: run or echo
# ---------------------------------------------------------------------------
run() {
    if $DRY_RUN; then
        echo "  [DRY] $*"
    else
        "$@"
    fi
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
START_TIME=$(date +%s)
LAST_CPU=""

for CPU in "${CPU_LIMITS[@]}"; do
    for WORKLOAD in "${WORKLOADS[@]}"; do
        for CLIENTS in "${CLIENT_COUNTS[@]}"; do
            CURRENT=$(( CURRENT + 1 ))
            log_step "Experiment $CURRENT/$TOTAL: CPU=$CPU  Workload=$WORKLOAD  Clients=$CLIENTS"

            OUTPUT_DIR="$RESULTS_DIR/cpu_${CPU}/${WORKLOAD}"
            METRICS_FILE="$OUTPUT_DIR/c${CLIENTS}_k8s_metrics.csv"

            mkdir -p "$OUTPUT_DIR"

            # ----------------------------------------------------------------
            # Re-deploy Redis only when CPU limit changes (saves time)
            # ----------------------------------------------------------------
            if [ "$CPU" != "$LAST_CPU" ]; then
                log_info "Deploying Redis with CPU limit $CPU..."
                run bash "$SCRIPT_DIR/deploy_redis.sh" "$CPU"
                LAST_CPU="$CPU"
                # Give Redis a moment to warm up
                $DRY_RUN || sleep 5
            fi

            # ----------------------------------------------------------------
            # Start background metrics collection
            # ----------------------------------------------------------------
            if ! $DRY_RUN; then
                bash "$SCRIPT_DIR/collect_metrics.sh" "$METRICS_FILE" 2 "$CPU" &
                METRICS_PID=$!
                log_info "Metrics collection started (PID $METRICS_PID)"
            else
                echo "  [DRY] start collect_metrics.sh → $METRICS_FILE"
            fi

            # ----------------------------------------------------------------
            # Run the benchmark
            # ----------------------------------------------------------------
            run bash "$SCRIPT_DIR/run_benchmark.sh" "$CPU" "$WORKLOAD" "$CLIENTS" "$OUTPUT_DIR"

            # ----------------------------------------------------------------
            # Stop metrics collection
            # ----------------------------------------------------------------
            if ! $DRY_RUN && [ -n "${METRICS_PID:-}" ]; then
                kill "$METRICS_PID" 2>/dev/null || true
                log_info "Metrics collection stopped."
            fi

            # Short pause between experiments
            $DRY_RUN || sleep 3

        done
    done
done

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
MINS=$(( ELAPSED / 60 ))
SECS=$(( ELAPSED % 60 ))

log_step "ALL EXPERIMENTS COMPLETE"
log_info "Total time: ${MINS}m ${SECS}s"
log_info "Results saved to: $RESULTS_DIR"
log_info ""
log_info "Next step: run the analysis script:"
log_info "  python3 $ANALYSIS_DIR/analyze_results.py"
