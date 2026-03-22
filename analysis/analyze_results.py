#!/usr/bin/env python3
"""
analyze_results.py - Parse and aggregate experiment results
SENG 533 - Group 25

Reads all CSVs from the results/ directory, computes per-configuration
averages across runs, and prints a summary table. Also saves a
consolidated CSV for use in the final report.

Usage:
    python3 analyze_results.py
    python3 analyze_results.py --results-dir ../results --output summary.csv
"""

import argparse
import csv
import os
import statistics
from collections import defaultdict
from pathlib import Path


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
DEFAULT_RESULTS_DIR = Path(__file__).parent.parent / "results"
DEFAULT_OUTPUT      = Path(__file__).parent / "summary.csv"

CPU_LIMITS  = ["0.25", "0.5", "1.0"]
WORKLOADS   = ["set", "get"]
CLIENTS     = [1, 10, 50, 100, 200]

METRICS = ["throughput_rps", "avg_latency_ms", "p50_latency_ms",
           "p95_latency_ms", "p99_latency_ms"]

K8S_METRICS = ["cpu_pct", "memory_mb_used"]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def safe_float(val):
    try:
        return float(val)
    except (ValueError, TypeError):
        return None


def load_csv(filepath):
    """Return list-of-dicts from a CSV file."""
    rows = []
    with open(filepath, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)
    return rows


def compute_stats(values):
    """Return (mean, stdev, min, max) for a list of floats, skipping None."""
    vals = [v for v in values if v is not None]
    if not vals:
        return None, None, None, None
    mean  = statistics.mean(vals)
    stdev = statistics.stdev(vals) if len(vals) > 1 else 0.0
    return mean, stdev, min(vals), max(vals)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Analyze redis-benchmark results")
    parser.add_argument("--results-dir", type=Path, default=DEFAULT_RESULTS_DIR)
    parser.add_argument("--output",      type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    results_dir = args.results_dir
    if not results_dir.exists():
        print(f"[ERROR] Results directory not found: {results_dir}")
        return

    # Accumulate per-config rows
    # key: (cpu_limit, workload, clients)
    # value: {metric: [values across runs]}
    data = defaultdict(lambda: defaultdict(list))

    for cpu in CPU_LIMITS:
        for wl in WORKLOADS:
            dir_path = results_dir / f"cpu_{cpu}" / wl
            if not dir_path.exists():
                continue
            for client in CLIENTS:
                key = (cpu, wl, client)

                # Benchmark metrics
                csv_file = dir_path / f"c{client}.csv"
                if csv_file.exists():
                    rows = load_csv(csv_file)
                    for row in rows:
                        for metric in METRICS:
                            val = safe_float(row.get(metric))
                            if val is not None:
                                data[key][metric].append(val)

                # K8s resource metrics (CPU %, memory MB)
                k8s_file = dir_path / f"c{client}_k8s_metrics.csv"
                if k8s_file.exists():
                    rows = load_csv(k8s_file)
                    for row in rows:
                        for metric in K8S_METRICS:
                            val = safe_float(row.get(metric))
                            if val is not None:
                                data[key][metric].append(val)

    if not data:
        print("[WARN] No result files found. Have you run experiments yet?")
        return

    # Build summary rows
    all_metrics = METRICS + K8S_METRICS
    summary_rows = []
    header = ["cpu_limit", "workload", "clients"] + [
        f"{m}_mean" for m in all_metrics
    ] + [
        f"{m}_stdev" for m in all_metrics
    ]

    for (cpu, wl, clients) in sorted(data.keys(), key=lambda x: (x[0], x[1], x[2])):
        row = {"cpu_limit": cpu, "workload": wl, "clients": clients}
        for metric in all_metrics:
            vals = data[(cpu, wl, clients)][metric]
            mean, stdev, mn, mx = compute_stats(vals)
            row[f"{metric}_mean"]  = f"{mean:.3f}"  if mean  is not None else "N/A"
            row[f"{metric}_stdev"] = f"{stdev:.3f}" if stdev is not None else "N/A"
        summary_rows.append(row)

    # ---------------------------------------------------------------------------
    # Print table to console
    # ---------------------------------------------------------------------------
    col_width = 12
    header_line = "  ".join(f"{h:<{col_width}}" for h in
                            ["cpu_limit", "workload", "clients",
                             "throughput", "avg_lat_ms", "p95_lat_ms", "p99_lat_ms",
                             "cpu_pct_%", "mem_mb"])
    print("\n" + "=" * len(header_line))
    print("RESULTS SUMMARY")
    print("=" * len(header_line))
    print(header_line)
    print("-" * len(header_line))
    for row in summary_rows:
        line = "  ".join(f"{str(row.get(k, 'N/A')):<{col_width}}" for k in
                         ["cpu_limit", "workload", "clients",
                          "throughput_rps_mean", "avg_latency_ms_mean",
                          "p95_latency_ms_mean", "p99_latency_ms_mean",
                          "cpu_pct_mean", "memory_mb_used_mean"])
        print(line)
    print("=" * len(header_line))

    # ---------------------------------------------------------------------------
    # Save full summary CSV
    # ---------------------------------------------------------------------------
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=header)
        writer.writeheader()
        writer.writerows(summary_rows)

    print(f"\n[INFO] Full summary saved to: {args.output}")


if __name__ == "__main__":
    main()
