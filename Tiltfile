# =============================================================================
# Tiltfile — SENG 533 Redis Benchmarking (Group 25)
# Usage:
#   tilt up                   # default CPU: 0.5
#   tilt up -- --cpu=0.25     # 0.25 CPU limit
#   tilt up -- --cpu=1.0      # 1.0 CPU limit
#
# Switch CPU while running:
#   tilt args -- --cpu=1.0
# =============================================================================

# ---------------------------------------------------------------------------
# 0. CLI args
# ---------------------------------------------------------------------------
config.define_string("cpu", usage="CPU limit for Redis: 0.25 | 0.5 | 1.0 (default: 0.5)")
cfg = config.parse()
CPU = cfg.get("cpu", "0.5")

VALID_CPUS = ["0.25", "0.5", "1.0"]
if CPU not in VALID_CPUS:
    fail("Invalid --cpu value '{}'. Valid values: {}".format(CPU, ", ".join(VALID_CPUS)))

# Safety guardrail: never accidentally target a production cluster
allow_k8s_contexts("minikube")

# ---------------------------------------------------------------------------
# 1. One-time environment setup (manual trigger)
# ---------------------------------------------------------------------------
local_resource(
    "minikube-setup",
    cmd="bash scripts/setup.sh",
    trigger_mode=TRIGGER_MODE_MANUAL,
    labels=["setup"],
)

# ---------------------------------------------------------------------------
# 2. Ensure results directory tree exists (auto, idempotent)
# ---------------------------------------------------------------------------
local_resource(
    "ensure-results-dirs",
    cmd="mkdir -p results/cpu_0.25/set results/cpu_0.25/get results/cpu_0.5/set results/cpu_0.5/get results/cpu_1.0/set results/cpu_1.0/get",
    trigger_mode=TRIGGER_MODE_AUTO,
    labels=["setup"],
)

# ---------------------------------------------------------------------------
# 3. Kubernetes manifests
# ---------------------------------------------------------------------------
k8s_yaml("k8s/redis-service.yaml")
k8s_yaml("k8s/redis-deployment-{}cpu.yaml".format(CPU))

# ---------------------------------------------------------------------------
# 4. Port-forward managed by Tilt (replaces manual kubectl port-forward)
# ---------------------------------------------------------------------------
k8s_resource(
    "redis",
    port_forwards=["6379:6379"],
    labels=["redis"],
)

# ---------------------------------------------------------------------------
# 5. Benchmark resources (manual trigger, depend on redis being ready)
# ---------------------------------------------------------------------------
local_resource(
    "bench-set",
    cmd="bash scripts/run_benchmark.sh {} set 50 results/cpu_{}/set".format(CPU, CPU),
    trigger_mode=TRIGGER_MODE_MANUAL,
    resource_deps=["redis", "ensure-results-dirs"],
    labels=["benchmark"],
)

local_resource(
    "bench-get",
    cmd="bash scripts/run_benchmark.sh {} get 50 results/cpu_{}/get".format(CPU, CPU),
    trigger_mode=TRIGGER_MODE_MANUAL,
    resource_deps=["redis", "ensure-results-dirs"],
    labels=["benchmark"],
)

local_resource(
    "run-all-experiments",
    cmd="bash scripts/run_all_experiments.sh",
    trigger_mode=TRIGGER_MODE_MANUAL,
    resource_deps=["minikube-setup", "ensure-results-dirs"],
    labels=["benchmark"],
)

local_resource(
    "analyze-results",
    cmd="python3 analysis/analyze_results.py",
    trigger_mode=TRIGGER_MODE_MANUAL,
    labels=["analysis"],
)

# ---------------------------------------------------------------------------
# 6. cmd_button UI buttons
# ---------------------------------------------------------------------------
cmd_button(
    name="btn-run-set",
    argv=["bash", "scripts/run_benchmark.sh", CPU, "set", "50",
          "results/cpu_{}/set".format(CPU)],
    resource="bench-set",
    text="Run SET (50 clients, cpu={})".format(CPU),
    icon_name="play_arrow",
)

cmd_button(
    name="btn-run-get",
    argv=["bash", "scripts/run_benchmark.sh", CPU, "get", "50",
          "results/cpu_{}/get".format(CPU)],
    resource="bench-get",
    text="Run GET (50 clients, cpu={})".format(CPU),
    icon_name="play_arrow",
)

cmd_button(
    name="btn-run-all",
    argv=["bash", "scripts/run_all_experiments.sh"],
    resource="run-all-experiments",
    text="Run ALL 30 experiments",
    icon_name="science",
)

cmd_button(
    name="btn-analyze",
    argv=["python3", "analysis/analyze_results.py"],
    resource="analyze-results",
    text="Analyze → summary.csv",
    icon_name="bar_chart",
)
