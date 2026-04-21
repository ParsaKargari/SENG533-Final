#!/usr/bin/env python3
"""
generate_plots.py - Generate all publication-quality figures for the final report.
SENG 533 - Group 25

Reads analysis/summary.csv and writes 11 PNG figures to report/figures/.

Usage:
    python3 analysis/generate_plots.py
"""

import csv
import math
from pathlib import Path
from collections import defaultdict

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR  = Path(__file__).parent
SUMMARY_CSV = SCRIPT_DIR / "summary.csv"
FIGURES_DIR = SCRIPT_DIR.parent / "report" / "figures"
FIGURES_DIR.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# Style
# ---------------------------------------------------------------------------
plt.rcParams.update({
    "font.family":      "serif",
    "font.size":        10,
    "axes.titlesize":   11,
    "axes.labelsize":   10,
    "xtick.labelsize":  9,
    "ytick.labelsize":  9,
    "legend.fontsize":  9,
    "lines.linewidth":  1.8,
    "lines.markersize": 6,
    "figure.dpi":       150,
    "savefig.dpi":      200,
    "savefig.bbox":     "tight",
})

CPU_COLORS  = {"0.25": "#d62728", "0.5": "#ff7f0e", "1.0": "#1f77b4"}
CPU_MARKERS = {"0.25": "o",       "0.5": "s",       "1.0": "^"}
CPU_LABELS  = {"0.25": "0.25 CPU", "0.5": "0.5 CPU", "1.0": "1.0 CPU"}
CLIENTS     = [1, 10, 50, 100, 200]

# 95% CI multiplier for n=3
T_95_N3 = 4.303  # t-distribution, df=2, two-tailed 95%

# ---------------------------------------------------------------------------
# Load data
# ---------------------------------------------------------------------------
def load_data(csv_path):
    """Return nested dict: data[cpu][workload][clients] = {col: value}"""
    data = defaultdict(lambda: defaultdict(dict))
    with open(csv_path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            cpu = row["cpu_limit"]
            wl  = row["workload"]
            c   = int(row["clients"])
            rec = {}
            for k, v in row.items():
                if k in ("cpu_limit", "workload", "clients"):
                    continue
                rec[k] = float(v) if v not in ("N/A", "") else None
            data[cpu][wl][c] = rec
    return data


def get_series(data, cpu, workload, metric):
    """Return (means, ci_half) lists over CLIENTS."""
    means, ci_halves = [], []
    for c in CLIENTS:
        rec  = data[cpu][workload].get(c, {})
        mean = rec.get(f"{metric}_mean")
        std  = rec.get(f"{metric}_stdev")
        means.append(mean)
        if mean is not None and std is not None:
            ci_halves.append(T_95_N3 * std / math.sqrt(3))
        else:
            ci_halves.append(None)
    return means, ci_halves


def _errorbars(ci_halves):
    """Convert CI half-widths to matplotlib yerr format (2-row array)."""
    lo = [v if v is not None else 0 for v in ci_halves]
    hi = [v if v is not None else 0 for v in ci_halves]
    return [lo, hi]


# ---------------------------------------------------------------------------
# Plot helpers
# ---------------------------------------------------------------------------
def line_chart(ax, data, workload, metric, ylabel, title):
    for cpu in ["0.25", "0.5", "1.0"]:
        means, cis = get_series(data, cpu, workload, metric)
        valid = [(c, m, e) for c, m, e in zip(CLIENTS, means, cis) if m is not None]
        if not valid:
            continue
        xs, ys, es = zip(*valid)
        eb = _errorbars(es)
        ax.errorbar(xs, ys, yerr=eb,
                    color=CPU_COLORS[cpu], marker=CPU_MARKERS[cpu],
                    label=CPU_LABELS[cpu], capsize=3, capthick=1.2)
    ax.set_xlabel("Number of Clients")
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    ax.set_xticks(CLIENTS)
    ax.legend()
    ax.grid(True, linestyle="--", alpha=0.4)


def save(fig, name):
    path = FIGURES_DIR / name
    fig.savefig(path)
    plt.close(fig)
    print(f"  saved: {path.name}")


# ---------------------------------------------------------------------------
# Figure generators
# ---------------------------------------------------------------------------
def fig_throughput(data, workload):
    fig, ax = plt.subplots(figsize=(5.5, 3.8))
    wl_label = "GET" if workload == "get" else "SET"
    line_chart(ax, data, workload, "throughput_rps",
               "Throughput (requests/sec)",
               f"{wl_label} Throughput vs. Number of Clients")
    ax.yaxis.set_major_formatter(ticker.FuncFormatter(lambda x, _: f"{x/1000:.0f}k"))
    save(fig, f"fig_throughput_{workload}.png")


def fig_avglat(data, workload):
    fig, ax = plt.subplots(figsize=(5.5, 3.8))
    wl_label = "GET" if workload == "get" else "SET"
    line_chart(ax, data, workload, "avg_latency_ms",
               "Average Latency (ms)",
               f"{wl_label} Average Latency vs. Number of Clients")
    save(fig, f"fig_avglat_{workload}.png")


def fig_p95(data, workload):
    fig, ax = plt.subplots(figsize=(5.5, 3.8))
    wl_label = "GET" if workload == "get" else "SET"
    line_chart(ax, data, workload, "p95_latency_ms",
               "p95 Latency (ms)",
               f"{wl_label} p95 Latency vs. Number of Clients")
    save(fig, f"fig_p95_{workload}.png")


def fig_p99(data, workload):
    fig, ax = plt.subplots(figsize=(5.5, 3.8))
    wl_label = "GET" if workload == "get" else "SET"
    line_chart(ax, data, workload, "p99_latency_ms",
               "p99 Latency (ms)",
               f"{wl_label} p99 Latency vs. Number of Clients")
    save(fig, f"fig_p99_{workload}.png")


def fig_get_vs_set_by_cpu(data):
    """Three side-by-side subplots: one per CPU limit, GET vs SET throughput."""
    fig, axes = plt.subplots(1, 3, figsize=(11, 3.8), sharey=True)
    for ax, cpu in zip(axes, ["0.25", "0.5", "1.0"]):
        for wl, color, marker in [("get", "#1f77b4", "o"), ("set", "#d62728", "s")]:
            means, cis = get_series(data, cpu, wl, "throughput_rps")
            valid = [(c, m, e) for c, m, e in zip(CLIENTS, means, cis) if m is not None]
            if not valid:
                continue
            xs, ys, es = zip(*valid)
            ax.errorbar(xs, ys, yerr=_errorbars(es),
                        color=color, marker=marker,
                        label=wl.upper(), capsize=3, capthick=1.2)
        ax.set_title(f"{CPU_LABELS[cpu]}")
        ax.set_xlabel("Number of Clients")
        ax.set_xticks(CLIENTS)
        ax.set_xticklabels(CLIENTS, rotation=45, ha="right")
        ax.grid(True, linestyle="--", alpha=0.4)
        ax.yaxis.set_major_formatter(ticker.FuncFormatter(lambda x, _: f"{x/1000:.0f}k"))
    axes[0].set_ylabel("Throughput (requests/sec)")
    axes[0].legend()
    fig.suptitle("GET vs. SET Throughput by CPU Limit", y=1.01)
    fig.tight_layout()
    save(fig, "fig_get_vs_set_by_cpu.png")


def fig_throughput_200clients(data):
    """Grouped bar chart: throughput at 200 clients, GET vs SET, grouped by CPU limit."""
    cpu_limits = ["0.25", "0.5", "1.0"]
    get_vals, set_vals = [], []
    get_errs, set_errs = [], []
    for cpu in cpu_limits:
        for wl, vals_list, errs_list in [("get", get_vals, get_errs),
                                          ("set", set_vals, set_errs)]:
            rec = data[cpu][wl].get(200, {})
            m   = rec.get("throughput_rps_mean")
            s   = rec.get("throughput_rps_stdev")
            vals_list.append(m if m is not None else 0)
            errs_list.append(T_95_N3 * s / math.sqrt(3) if s is not None else 0)

    x      = np.arange(len(cpu_limits))
    width  = 0.35
    fig, ax = plt.subplots(figsize=(5.5, 3.8))
    bars_get = ax.bar(x - width/2, [v/1000 for v in get_vals], width,
                      label="GET", color="#1f77b4",
                      yerr=[e/1000 for e in get_errs], capsize=4)
    bars_set = ax.bar(x + width/2, [v/1000 for v in set_vals], width,
                      label="SET", color="#d62728",
                      yerr=[e/1000 for e in set_errs], capsize=4)
    ax.set_xlabel("CPU Limit (cores)")
    ax.set_ylabel("Throughput (k requests/sec)")
    ax.set_title("Throughput at 200 Clients by CPU Limit")
    ax.set_xticks(x)
    ax.set_xticklabels(cpu_limits)
    ax.legend()
    ax.grid(True, axis="y", linestyle="--", alpha=0.4)
    save(fig, "fig_throughput_200clients.png")


def fig_cpu_utilization_get(data):
    """GET CPU utilization % vs concurrency for each CPU limit."""
    fig, ax = plt.subplots(figsize=(5.5, 3.8))
    for cpu in ["0.25", "0.5", "1.0"]:
        xs, ys = [], []
        for c in CLIENTS:
            rec = data[cpu]["get"].get(c, {})
            val = rec.get("cpu_pct_mean")
            if val is not None:
                xs.append(c)
                ys.append(val)
        if xs:
            ax.plot(xs, ys,
                    color=CPU_COLORS[cpu], marker=CPU_MARKERS[cpu],
                    label=CPU_LABELS[cpu])
    ax.set_xlabel("Number of Clients")
    ax.set_ylabel("CPU Utilization (%)")
    ax.set_title("GET CPU Utilization vs. Number of Clients")
    ax.set_xticks(CLIENTS)
    ax.legend()
    ax.grid(True, linestyle="--", alpha=0.4)
    save(fig, "fig_cpu_utilization_get.png")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print(f"Reading: {SUMMARY_CSV}")
    data = load_data(SUMMARY_CSV)
    print(f"Generating figures into: {FIGURES_DIR}\n")

    for wl in ["get", "set"]:
        fig_throughput(data, wl)
        fig_avglat(data, wl)
        fig_p95(data, wl)
        fig_p99(data, wl)

    fig_get_vs_set_by_cpu(data)
    fig_throughput_200clients(data)
    fig_cpu_utilization_get(data)

    print("\nDone. All 11 figures generated.")


if __name__ == "__main__":
    main()
