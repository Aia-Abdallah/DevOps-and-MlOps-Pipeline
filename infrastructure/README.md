# CISC-814 Infrastructure Setup

This directory contains the infrastructure configuration for the CISC-814 DevOps and MLOps course.

## Local Development Environment

The `docker-compose.yml` provides a local development stack that mirrors the course Kubernetes cluster. Use this for experimentation and testing before deploying to the cluster.

### Components

| Service | Port | Description |
|---------|------|-------------|
| Gitea | 3000 | Git server with Actions support |
| Gitea SSH | 2222 | Git SSH access |
| Container Registry | 5001 | Docker image storage |
| Registry UI | 5002 | Registry web interface |
| MLflow | 5050 | ML experiment tracking |
| Prometheus | 9090 | Metrics collection |
| Grafana | 3001 | Dashboards and visualization |
| OTel Collector | 4317/4318 | OpenTelemetry ingestion |
| Evidently | 8085 | ML drift monitoring |

### Quick Start

```bash
# Start all services
docker compose up -d

# View logs
docker compose logs -f

# Stop all services
docker compose down

# Stop and remove volumes (full cleanup)
docker compose down -v
```

### Service Access

After starting the stack:

1. **Gitea** (Git Server): http://localhost:3000
   - First-time setup: Create admin account
   - Configure SSH key for Git operations

2. **MLflow**: http://localhost:5050
   - No authentication required for local use
   - Create experiments and log runs

3. **Grafana**: http://localhost:3001
   - Username: `admin`
   - Password: `admin`
   - Prometheus datasource pre-configured

4. **Container Registry**: http://localhost:5001
   - Push images: `docker tag myimage localhost:5001/myimage && docker push localhost:5001/myimage`
   - View UI: http://localhost:5002

5. **Prometheus**: http://localhost:9090
   - Query metrics
   - View targets at /targets

6. **Evidently**: http://localhost:8085
   - ML monitoring dashboards

### Gitea Actions Setup

To enable CI/CD with Gitea Actions:

1. Start the stack: `docker compose up -d`
2. Access Gitea: http://localhost:3000
3. Create admin account and a repository
4. Go to Site Administration > Actions > Runners
5. Generate a registration token
6. Set the token in your environment:
   ```bash
   export GITEA_RUNNER_TOKEN=<your-token>
   docker compose up -d gitea-runner
   ```

### Connecting Applications

To connect your applications to this stack:

**MLflow Tracking:**
```python
import mlflow
mlflow.set_tracking_uri("http://localhost:5050")
mlflow.set_experiment("my-experiment")
```

**Push to Registry:**
```bash
docker build -t localhost:5001/my-app:v1 .
docker push localhost:5001/my-app:v1
```

**Send Metrics (OpenTelemetry):**
```python
from opentelemetry import metrics
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader

exporter = OTLPMetricExporter(endpoint="localhost:4317", insecure=True)
reader = PeriodicExportingMetricReader(exporter)
provider = MeterProvider(metric_readers=[reader])
metrics.set_meter_provider(provider)
```

---

## Kubernetes Cluster Setup (Per-Team k3d Clusters)

Each team gets its own isolated Kubernetes cluster using **k3d** (k3s-in-Docker). All clusters share the Docker network with the compose services, so pods can reach Gitea, the registry, MLflow, etc. via Docker DNS.

### Architecture

```
┌──────────────────────────────────────────────────────────────┐
│ Docker Host                                                  │
│                                                              │
│  docker-compose services (cisc814-network)                   │
│  ┌────────┐ ┌──────────┐ ┌────────┐ ┌──────────┐            │
│  │ Gitea  │ │ Registry │ │ MLflow │ │Prometheus│ ...         │
│  └───┬────┘ └────┬─────┘ └───┬────┘ └────┬─────┘            │
│      └───────────┴───────────┴────────────┘                  │
│                  cisc814-network                             │
│      ┌───────────┬───────────┬────────────┐                  │
│  ┌───┴────┐ ┌────┴────┐ ┌───┴────┐ ┌─────┴──┐               │
│  │ k3d    │ │ k3d     │ │ k3d    │ │ k3d    │               │
│  │ alpha  │ │ beta    │ │ gamma  │ │ delta  │               │
│  └────────┘ └─────────┘ └────────┘ └────────┘               │
└──────────────────────────────────────────────────────────────┘
```

### Prerequisites

- Docker installed and running
- `kubectl` installed
- **k3d** installed:
  ```bash
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  ```
- Shared services running (`docker compose up -d` in this directory)

### Instructor Workflow: Create Team Clusters

```bash
# Create a single team cluster
./k3d/manage-cluster.sh create alpha

# Create clusters for all teams from a file (one team name per line)
./k3d/manage-cluster.sh create-all teams.txt

# List all CISC-814 clusters
./k3d/manage-cluster.sh list

# Delete a team cluster
./k3d/manage-cluster.sh delete alpha
```

The script generates a kubeconfig file per team in `k3d/kubeconfigs/`. Distribute the appropriate file to each team.

### Student Workflow: Access Your Cluster

1. Receive your kubeconfig file from the instructor
2. Set it as your active config:
   ```bash
   export KUBECONFIG=path/to/cisc814-<team>.yaml
   ```
3. Verify access:
   ```bash
   kubectl get nodes
   kubectl get all
   ```

### Reaching Shared Services from Pods

Pods inside k3d clusters can reach the shared compose services via Docker DNS:

| Service | URL from inside pods |
|---------|---------------------|
| Gitea | `http://cisc814-gitea:3000` |
| Container Registry | `http://cisc814-registry:5000` |
| MLflow | `http://cisc814-mlflow:5000` |
| Prometheus | `http://cisc814-prometheus:9090` |
| Grafana | `http://cisc814-grafana:3000` |

The registry is also configured as a mirror at `registry.local:5000` inside each cluster.

### Resource Quotas

Each cluster's `default` namespace has the following quotas applied automatically:

```yaml
requests.cpu: "4"
requests.memory: 8Gi
limits.cpu: "8"
limits.memory: 16Gi
pods: "20"
services: "10"
persistentvolumeclaims: "5"
```

Default container limits (via LimitRange): 500m CPU / 512Mi memory; default requests: 100m CPU / 128Mi memory.

---

## Troubleshooting

### Docker Compose Issues

**Services won't start:**
```bash
# Check if ports are in use
lsof -i :3000  # Gitea
lsof -i :5050  # MLflow

# View detailed logs
docker compose logs gitea
docker compose logs mlflow
```

**Database connection errors:**
```bash
# Restart databases
docker compose restart gitea-db mlflow-db

# Check database health
docker compose exec mlflow-db pg_isready -U mlflow
```

### k3d Cluster Issues

**Cluster won't start:**
```bash
# Ensure the Docker network exists
docker network ls | grep cisc814-network

# If not, start shared services first
docker compose up -d

# Check Docker resources — k3d clusters need sufficient memory
docker system info | grep Memory
```

**Pods stuck in Pending:**
```bash
kubectl describe pod <pod-name>
# Check Events section for resource quota issues
kubectl get resourcequota -o yaml
```

**Cannot reach shared services from pods:**
```bash
# Verify the cluster is on the correct network
docker network inspect cisc814-network | grep cisc814-

# Test connectivity from inside a pod
kubectl delete pod test --ignore-not-found
kubectl run test --rm -it --restart=Never --image=busybox -- wget -qO- -T 5 http://cisc814-gitea:3000
```

**Image pull errors:**
```bash
# Verify image exists in registry
curl http://localhost:5001/v2/_catalog

# From inside the cluster, use the mirror
# Images should be tagged as: registry.local:5000/<image>:<tag>
```

**ArgoCD sync issues:**
```bash
# Check application status
argocd app get <app-name>

# Force sync
argocd app sync <app-name> --force
```

---

## Files in this Directory

```
infrastructure/
├── docker-compose.yml      # Local development stack (shared services)
├── k3d/
│   ├── cluster-config.yaml.tpl  # k3d cluster config template
│   ├── manage-cluster.sh        # Cluster lifecycle script
│   ├── manifests/
│   │   ├── resource-quota.yaml  # Per-cluster resource quota
│   │   └── limit-range.yaml     # Default container limits
│   └── kubeconfigs/             # Generated kubeconfigs (gitignored)
├── prometheus/
│   └── prometheus.yml      # Prometheus scrape configuration
├── grafana/
│   └── provisioning/
│       └── datasources/
│           └── datasources.yml
├── otel/
│   └── otel-config.yml     # OpenTelemetry Collector config
└── README.md               # This file
```

---

## Additional Resources

- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Gitea Documentation](https://docs.gitea.com/)
- [MLflow Documentation](https://mlflow.org/docs/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
