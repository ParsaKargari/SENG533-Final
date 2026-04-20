# SENG 533 – Group 25
## Performance Characterization of Redis in a Containerized Kubernetes Deployment

---

## Prerequisites

Install the following on your host machine before running anything:

| Tool | Version | Notes |
|------|---------|-------|
| Docker | 20+ | Required by Minikube |
| Minikube | 1.32+ | Kubernetes local cluster |
| kubectl | 1.28+ | Cluster management |
| redis-benchmark | 7.x | Ships with Redis client tools |
| redis-cli | 7.x | Used for validation pings |
| Python 3 | 3.9+ | For analysis script only |
| Tilt | 0.33+ | Optional — for Tilt-based workflow |

---

## Project Structure

```
.
├── k8s/
│   ├── redis-deployment-0.25cpu.yaml   # Redis pod — 0.25 core limit
│   ├── redis-deployment-0.5cpu.yaml    # Redis pod — 0.5 core limit
│   ├── redis-deployment-1cpu.yaml      # Redis pod — 1.0 core limit
│   └── redis-service.yaml              # ClusterIP service (port 6379)
│
├── scripts/
│   ├── setup.sh                # One-time environment setup
│   ├── deploy_redis.sh         # Deploy Redis with a given CPU limit
│   ├── run_benchmark.sh        # Run a single benchmark configuration
│   ├── collect_metrics.sh      # Background Kubernetes metrics collector
│   └── run_all_experiments.sh  # Master runner — all 30 configurations
│
├── results/                    # Auto-created; populated after experiments
│   └── cpu_<limit>/
│       └── <workload>/
│           ├── c<clients>.csv              # Parsed metrics (3 runs)
│           ├── c<clients>_raw.txt          # Raw redis-benchmark output
│           └── c<clients>_k8s_metrics.csv  # Kubernetes CPU/memory samples
│
└── analysis/
    ├── analyze_results.py      # Aggregation + summary CSV
    └── summary.csv             # Generated after running analysis
```

---

## Experiment Matrix

| Factor | Levels |
|--------|--------|
| CPU Limit (Kubernetes) | 0.25 cores, 0.5 cores, 1.0 core |
| Workload | SET-only, GET-only |
| Concurrency (clients) | 1, 10, 50, 100, 200 |
| Runs per config | 3 (averaged) |
| Total requests per run | 10,000 (fixed across all configs) |
| **Total configurations** | **30** |

---

## Quick Start

### Linux / macOS

#### Step 1 — One-time setup
```bash
chmod +x scripts/*.sh
./scripts/setup.sh
```

This will:
- Verify Docker, Minikube, kubectl, and redis-benchmark are installed
- Start Minikube with 4 CPUs and 4 GB RAM
- Enable the `metrics-server` addon
- Apply the Redis Kubernetes Service
- Create the results directory structure

#### Step 2 — Run all experiments
```bash
./scripts/run_all_experiments.sh
```

To preview what will run without executing anything:
```bash
./scripts/run_all_experiments.sh --dry-run
```

#### Step 3 — Analyze results
```bash
python3 analysis/analyze_results.py
```

This prints a summary table and saves `analysis/summary.csv`.

---

### Windows (via WSL2)

All scripts are Bash — on Windows you must run them inside **WSL2** (Windows Subsystem for Linux).

#### Step 1 — Enable WSL2
Open PowerShell as Administrator and run:
```powershell
wsl --install
```
Restart your computer when prompted. This installs WSL2 with Ubuntu by default.

#### Step 2 — Install Docker Desktop
Download and install [Docker Desktop](https://www.docker.com/products/docker-desktop/), then:
- **Settings → General** → enable "Use the WSL 2 based engine"
- **Settings → Resources → WSL Integration** → enable for **Ubuntu**

Make sure Docker Desktop is running before continuing.

#### Step 3 — Install dependencies inside WSL (Ubuntu terminal)
Open the Ubuntu app from the Start menu, then:
```bash
sudo apt update && sudo apt install -y redis-tools python3 curl
```

#### Step 4 — Install kubectl inside WSL
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
```

#### Step 5 — Install Minikube inside WSL
```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm minikube-linux-amd64
```

#### Step 6 — Navigate to the project and set up
Your Windows `C:\` drive is accessible at `/mnt/c` inside WSL:
```bash
cd /mnt/c/Users/<your-username>/Desktop/Developer/SENG533-Final
chmod +x scripts/*.sh
./scripts/setup.sh
```

#### Step 7 — Run all experiments
```bash
./scripts/run_all_experiments.sh
```

To preview without executing:
```bash
./scripts/run_all_experiments.sh --dry-run
```

#### Step 8 — Analyze results
```bash
python3 analysis/analyze_results.py
```

---

## Quick Start with Tilt (Recommended)

Tilt provides a live dashboard UI at `http://localhost:10350` and manages pod deployment and port-forwarding automatically.

### Install Tilt

```bash
curl -fsSL https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | bash
```

### First-time setup

```bash
bash scripts/setup.sh    # start Minikube, enable metrics-server, apply service, create results dirs
tilt up                  # starts Tilt UI with default CPU limit of 0.5
```

For subsequent sessions where Minikube has stopped, click **minikube-setup → Run** in the Tilt dashboard to re-run `setup.sh` (it safely skips `minikube start` if already running).

### Switching CPU configurations

```bash
# While Tilt is running, switch the active CPU limit:
tilt args -- --cpu=0.25    # 0.25-core limit
tilt args -- --cpu=0.5     # 0.5-core limit (default)
tilt args -- --cpu=1.0     # 1.0-core limit
```

Tilt automatically re-deploys Redis and re-establishes port-forwarding. No manual `kubectl` commands needed.

### Running experiments via the Tilt UI

| Button | What it does |
|--------|-------------|
| **Run GET (50 clients)** | Quick GET benchmark at the current CPU limit |
| **Run SET (50 clients)** | Quick SET benchmark at the current CPU limit |
| **Run ALL 30 experiments** | Full experiment suite across all 30 configs (~2–3 hrs) |
| **Analyze → summary.csv** | Aggregate raw results into `analysis/summary.csv` |

All benchmark output streams live in the Tilt UI log pane.

### Teardown

```bash
tilt down        # removes Kubernetes resources; leaves Minikube running
minikube stop    # optional: stop Minikube entirely
```

---

## Running a Single Experiment

```bash
# Deploy Redis with a specific CPU limit
./scripts/deploy_redis.sh 0.5

# Run one configuration manually
./scripts/run_benchmark.sh 0.5 set 50 results/cpu_0.5/set
```

---

## Metrics Collected

| Metric | Source |
|--------|--------|
| Throughput (requests/sec) | redis-benchmark |
| Average latency (ms) | redis-benchmark |
| p50 latency (ms) | redis-benchmark |
| p95 latency (ms) | redis-benchmark |
| p99 latency (ms) | redis-benchmark |
| CPU utilization (% of limit) | kubectl top pod |
| Memory usage (MB) | kubectl top pod |

---

## Group Members

- Axel Omar Sanchez Peralta (30145429)
- Mariia Podgaietska (30151330)
- Parsa Kargari (30143368)
- Prosper Ademoye (30143058)
- Bernard Aire (30112955)
