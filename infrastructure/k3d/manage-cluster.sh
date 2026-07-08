#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/cluster-config.yaml.tpl"
TEMPLATE_GPU="${SCRIPT_DIR}/cluster-config-gpu.yaml.tpl"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"
KUBECONFIGS_DIR="${SCRIPT_DIR}/kubeconfigs"
NETWORK_NAME="cisc814-network"
CLUSTER_PREFIX="cisc814"
GPU_IMAGE="k3s-cuda:local"
ARGOCD_BASE_PORT=8400      # Each team gets next available port
GRAFANA_BASE_PORT=8500
PROMETHEUS_BASE_PORT=8600

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [arguments]

Commands:
  create [--gpu] [--volume PATH_ON_HOST:PATH_IN_CONTAINER ...] <team-name>
                            Create a k3d cluster for a team; --gpu enables NVIDIA GPU support
                            for assignment 2, while --volume optionally mounts a local path as a volume
  delete <team-name>          Delete a team's k3d cluster
  info <team-name>            Show cluster connection details (kubeconfig, ArgoCD URL, etc.)
  list                        List all CISC-814 k3d clusters
  ensure-components <team>    Ensure ArgoCD + Argo Rollouts are installed on an existing cluster
  build-gpu-image [--no-cache] Build the custom k3s CUDA image for GPU support
  create-all [--gpu] <file>   Create clusters for all teams listed in file (one per line)

Examples:
  $(basename "$0") create alpha
  $(basename "$0") create --gpu alpha
  $(basename "$0") build-gpu-image
  $(basename "$0") info alpha
  $(basename "$0") delete alpha
  $(basename "$0") list
  $(basename "$0") create-all teams.txt
EOF
    exit 1
}

validate_team_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-z0-9]([a-z0-9-]{0,18}[a-z0-9])?$ ]]; then
        echo "Error: Team name must be 1-20 lowercase alphanumeric characters or hyphens,"
        echo "       must start and end with an alphanumeric character."
        exit 1
    fi
}

check_network() {
    if ! docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}$"; then
        echo "Error: Docker network '${NETWORK_NAME}' not found."
        echo "Start the shared services first:"
        echo "  cd ${SCRIPT_DIR}/.. && docker compose up -d"
        exit 1
    fi
}

check_k3d() {
    if ! command -v k3d &>/dev/null; then
        echo "Error: k3d is not installed."
        echo "Install it with:"
        echo "  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash"
        exit 1
    fi
}

port_in_use() {
    # ss works without root; fall back to lsof
    ss -tlnH "sport = :$1" 2>/dev/null | grep -q ":$1 " \
        || lsof -iTCP:"$1" -sTCP:LISTEN &>/dev/null
}

next_argocd_port() {
    local port=${ARGOCD_BASE_PORT}
    while port_in_use "${port}"; do
        port=$((port + 1))
    done
    echo "${port}"
}

next_grafana_port() {
    local port=${GRAFANA_BASE_PORT}
    while port_in_use "${port}"; do
        port=$((port + 1))
    done
    echo "${port}"
}

next_prometheus_port() {
    local port=${PROMETHEUS_BASE_PORT}
    while port_in_use "${port}"; do
        port=$((port + 1))
    done
    echo "${port}"
}

install_cluster_components() {
    local context="$1"   # e.g. "k3d-cisc814-a2-test"

    # Install ArgoCD (idempotent)
    if ! kubectl --context "$context" get crd applications.argoproj.io &>/dev/null; then
        echo "Installing ArgoCD..."
        kubectl --context "$context" create namespace argocd 2>/dev/null || true
        kubectl --context "$context" apply -n argocd \
            -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
            --server-side
    else
        echo "ArgoCD already installed."
    fi

    # Install Argo Rollouts (idempotent)
    if ! kubectl --context "$context" get crd analysistemplates.argoproj.io &>/dev/null; then
        echo "Installing Argo Rollouts..."
        kubectl --context "$context" create namespace argo-rollouts 2>/dev/null || true
        kubectl --context "$context" apply -n argo-rollouts \
            -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
    else
        echo "Argo Rollouts already installed."
    fi

    # Wait for CRDs
    echo "Waiting for Argo CRDs to be established..."
    kubectl --context "$context" wait --for=condition=Established crd/applications.argoproj.io --timeout=60s
    kubectl --context "$context" wait --for=condition=Established crd/analysistemplates.argoproj.io --timeout=60s
    kubectl --context "$context" wait --for=condition=Established crd/rollouts.argoproj.io --timeout=60s

    # Run ArgoCD in insecure mode (no TLS) so it works behind SSH tunnels / NodePort
    echo "Configuring ArgoCD for insecure access..."
    kubectl --context "$context" -n argocd patch configmap argocd-cmd-params-cm \
        --type merge -p '{"data":{"server.insecure":"true"}}'
    # Restart the server to pick up the config change
    kubectl --context "$context" -n argocd rollout restart deployment argocd-server

    # Expose ArgoCD UI via NodePort on port 30080 (idempotent patch)
    echo "Ensuring ArgoCD UI is exposed via NodePort..."
    kubectl --context "$context" patch svc argocd-server -n argocd \
        --type merge -p '{"spec":{"type":"NodePort","ports":[{"port":443,"targetPort":8080,"nodePort":30080}]}}'
}

ensure_gpu_ready() {
    local context="$1"

    # The NVIDIA device plugin + RuntimeClass are auto-deployed by the custom
    # k3s-cuda image via /var/lib/rancher/k3s/server/manifests/.  Just wait
    # for the DaemonSet to be ready and GPUs to be advertised.
    echo "Waiting for NVIDIA device plugin..."
    kubectl --context "$context" -n kube-system rollout status daemonset/nvidia-device-plugin-daemonset --timeout=120s

    echo "Waiting for GPUs to be advertised..."
    local retries=0
    while [[ $retries -lt 30 ]]; do
        local gpu_count
        gpu_count=$(kubectl --context "$context" get nodes -o json \
            | python3 -c "import sys,json; nodes=json.load(sys.stdin)['items']; print(sum(int(n['status'].get('capacity',{}).get('nvidia.com/gpu','0')) for n in nodes))" 2>/dev/null || echo "0")
        if [[ "$gpu_count" -gt 0 ]]; then
            echo "  ${gpu_count} GPU(s) available."
            return 0
        fi
        retries=$((retries + 1))
        sleep 2
    done
    echo "Warning: GPUs not yet advertised. Check device plugin logs:"
    echo "  kubectl --context $context logs -n kube-system -l name=nvidia-device-plugin-ds"
}

cmd_build_gpu_image() {
    local no_cache=""
    if [[ "${1:-}" == "--no-cache" ]]; then
        no_cache="--no-cache"
    fi
    echo "Building custom k3s CUDA image '${GPU_IMAGE}'..."
    docker build $no_cache -t "${GPU_IMAGE}" -f "${SCRIPT_DIR}/Dockerfile.k3s-cuda" "${SCRIPT_DIR}"
    echo "Image '${GPU_IMAGE}' built successfully."
}

cmd_create() {
    local gpu=false
    local volumes=()
    while [[ "${1:-}" == --* ]]; do
        case "$1" in
            --gpu) gpu=true; shift ;;
            --volume) volumes+=("$2"); shift 2 ;;
            *) echo "Unknown option: $1"; usage ;;
        esac
    done

    local team="$1"
    local cluster_name="${CLUSTER_PREFIX}-${team}"

    validate_team_name "$team"
    check_k3d
    check_network

    # Check if cluster already exists
    if k3d cluster list -o json 2>/dev/null | grep -q "\"name\":\"${cluster_name}\""; then
        echo "Error: Cluster '${cluster_name}' already exists."
        echo "Delete it first: $(basename "$0") delete ${team}"
        exit 1
    fi

    # For GPU mode, verify the custom image exists
    if $gpu; then
        if ! docker image inspect "${GPU_IMAGE}" &>/dev/null; then
            echo "Error: GPU image '${GPU_IMAGE}' not found."
            echo "Build it first: $(basename "$0") build-gpu-image"
            exit 1
        fi
    fi

    # Assign unique ports
    local argocd_port grafana_port prometheus_port
    argocd_port=$(next_argocd_port)
    grafana_port=$(next_grafana_port)
    prometheus_port=$(next_prometheus_port)

    # Generate config from template
    local config tpl
    config=$(mktemp /tmp/k3d-config-XXXXXX.yaml)
    if $gpu; then
        tpl="$TEMPLATE_GPU"
    else
        tpl="$TEMPLATE"
    fi
    sed -e "s/TEAM_NAME/${team}/g" \
        -e "s/ARGOCD_PORT/${argocd_port}/g" \
        -e "s/GRAFANA_PORT/${grafana_port}/g" \
        -e "s/PROMETHEUS_PORT/${prometheus_port}/g" \
        -e "s|K3S_IMAGE|${GPU_IMAGE}|g" \
        "$tpl" > "$config"

    # Append host volume mounts if any were requested
    if [[ ${#volumes[@]} -gt 0 ]]; then
        echo "volumes:" >> "$config"
        for v in "${volumes[@]}"; do
            echo "  - volume: $v" >> "$config"
            echo "    nodeFilters:" >> "$config"
            echo "      - server:*" >> "$config"
        done
    fi

    echo "Creating k3d cluster '${cluster_name}'$(if $gpu; then echo ' (GPU enabled)'; fi)..."
    k3d cluster create --config "$config"
    rm -f "$config"

    # Wait for cluster to be ready
    echo "Waiting for cluster to be ready..."
    kubectl --context "k3d-${cluster_name}" wait --for=condition=Ready nodes --all --timeout=60s

    # Apply resource quota and limit range
    echo "Applying resource quota and limit range..."
    kubectl --context "k3d-${cluster_name}" apply -f "${MANIFESTS_DIR}/resource-quota.yaml"
    kubectl --context "k3d-${cluster_name}" apply -f "${MANIFESTS_DIR}/limit-range.yaml"

    # Install ArgoCD and Argo Rollouts
    install_cluster_components "k3d-${cluster_name}"

    # Wait for GPU readiness if GPU mode
    if $gpu; then
        ensure_gpu_ready "k3d-${cluster_name}"
    fi

    # Install kube-prometheus-stack (Prometheus + Grafana + prometheus-operator)
    echo "Installing kube-prometheus-stack..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    helm repo update prometheus-community # --fail-on-repo-update-fail=false
    helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        --kube-context "k3d-${cluster_name}" \
        --namespace monitoring --create-namespace \
        --set alertmanager.enabled=false \
        --set grafana.service.type=NodePort \
        --set grafana.service.nodePort=30081 \
        --set prometheus.service.type=NodePort \
        --set prometheus.service.nodePort=30090 \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
        --wait --timeout=300s

    # Install loki and alloy
    echo "Installing loki and alloy..."
    helm repo add grafana-community https://grafana-community.github.io/helm-charts
    helm repo update grafana-community
    helm upgrade --install loki grafana-community/loki \
         --namespace loki --create-namespace \
         --values "${MANIFESTS_DIR}/loki-values.yaml" \
         --wait --timeout=5m

    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update grafana
    helm upgrade --install alloy-logs grafana/alloy \
         --namespace monitoring \
         --values "${MANIFESTS_DIR}/alloy-values.yaml" \
         --wait --timeout=3m

    # Install Prometheus Pushgateway (for analysis jobs to push metrics)
    echo "Installing Prometheus Pushgateway..."
    helm upgrade --install prometheus-pushgateway prometheus-community/prometheus-pushgateway \
        --kube-context "k3d-${cluster_name}" \
        --namespace monitoring \
        --set service.port=9091 \
        --wait --timeout=120s

    # Wait for ArgoCD to be ready
    echo "Waiting for ArgoCD to be ready..."
    kubectl --context "k3d-${cluster_name}" wait --for=condition=Ready pods --all -n argocd --timeout=180s

    # Get ArgoCD admin password
    local argocd_password
    argocd_password=$(kubectl --context "k3d-${cluster_name}" -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)

    # Get Grafana admin password
    local grafana_password
    grafana_password=$(kubectl --context "k3d-${cluster_name}" -n monitoring \
        get secret kube-prometheus-stack-grafana \
        -o jsonpath='{.data.admin-password}' | base64 -d)

    # Export kubeconfig and save cluster metadata
    local kubeconfig="${KUBECONFIGS_DIR}/${cluster_name}.yaml"
    local metafile="${KUBECONFIGS_DIR}/${cluster_name}.env"
    k3d kubeconfig get "${cluster_name}" > "$kubeconfig"
    cat > "$metafile" <<ENVEOF
ARGOCD_PORT=${argocd_port}
ARGOCD_PASSWORD=${argocd_password}
GRAFANA_PORT=${grafana_port}
GRAFANA_PASSWORD=${grafana_password}
PROMETHEUS_PORT=${prometheus_port}
ENVEOF

    cmd_info "$team"
}

cmd_info() {
    local team="$1"
    local cluster_name="${CLUSTER_PREFIX}-${team}"

    check_k3d

    # Verify cluster exists
    if ! k3d cluster list -o json 2>/dev/null | grep -q "\"name\":\"${cluster_name}\""; then
        echo "Error: Cluster '${cluster_name}' does not exist."
        exit 1
    fi

    local kubeconfig="${KUBECONFIGS_DIR}/${cluster_name}.yaml"
    local metafile="${KUBECONFIGS_DIR}/${cluster_name}.env"

    # Read saved metadata
    local argocd_port argocd_password grafana_port grafana_password prometheus_port
    if [[ -f "$metafile" ]]; then
        # shellcheck disable=SC1090
        source "$metafile"
        argocd_port="${ARGOCD_PORT:-unknown}"
        argocd_password="${ARGOCD_PASSWORD:-unknown}"
        grafana_port="${GRAFANA_PORT:-unknown}"
        grafana_password="${GRAFANA_PASSWORD:-unknown}"
        prometheus_port="${PROMETHEUS_PORT:-unknown}"
    else
        # Fallback: read port from k3d and password from cluster
        argocd_port=$(docker inspect "k3d-${cluster_name}-server-0" 2>/dev/null \
            | python3 -c "import sys,json; ports=json.load(sys.stdin)[0]['NetworkSettings']['Ports'].get('30080/tcp',[]); print(ports[0]['HostPort'] if ports else 'unknown')" 2>/dev/null || echo "unknown")
        argocd_password=$(kubectl --context "k3d-${cluster_name}" -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "unknown")
        grafana_port=$(docker inspect "k3d-${cluster_name}-server-0" 2>/dev/null \
            | python3 -c "import sys,json; ports=json.load(sys.stdin)[0]['NetworkSettings']['Ports'].get('30081/tcp',[]); print(ports[0]['HostPort'] if ports else 'unknown')" 2>/dev/null || echo "unknown")
        grafana_password=$(kubectl --context "k3d-${cluster_name}" -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "unknown")
        prometheus_port=$(docker inspect "k3d-${cluster_name}-server-0" 2>/dev/null \
            | python3 -c "import sys,json; ports=json.load(sys.stdin)[0]['NetworkSettings']['Ports'].get('30090/tcp',[]); print(ports[0]['HostPort'] if ports else 'unknown')" 2>/dev/null || echo "unknown")
    fi

    echo ""
    echo "============================================"
    echo "Cluster: ${cluster_name}"
    echo "============================================"
    echo ""
    echo "Kubeconfig: ${kubeconfig}"
    echo ""
    echo "To use this cluster:"
    echo "  export KUBECONFIG=${kubeconfig}"
    echo "  kubectl get nodes"
    echo ""
    echo "Shared services (accessible from pods via Docker DNS):"
    echo "  Gitea:    http://cisc814-gitea:3000"
    echo "  Registry: http://cisc814-registry:5000"
    echo "  MLflow:   http://cisc814-mlflow:5000"
    echo ""
    echo "ArgoCD UI:     https://localhost:${argocd_port}"
    echo "  Username: admin  Password: ${argocd_password}"
    echo ""
    echo "Grafana UI:    http://localhost:${grafana_port}"
    echo "  Username: admin  Password: ${grafana_password}"
    echo ""
    echo "Prometheus UI: http://localhost:${prometheus_port}"
    echo ""
}

cmd_delete() {
    local team="$1"
    local cluster_name="${CLUSTER_PREFIX}-${team}"

    check_k3d

    echo "Deleting k3d cluster '${cluster_name}'..."
    k3d cluster delete "${cluster_name}"

    local kubeconfig="${KUBECONFIGS_DIR}/${cluster_name}.yaml"
    local metafile="${KUBECONFIGS_DIR}/${cluster_name}.env"
    for f in "$kubeconfig" "$metafile"; do
        if [[ -f "$f" ]]; then
            rm -f "$f"
            echo "Removed: ${f}"
        fi
    done

    echo "Cluster '${cluster_name}' deleted."
}

cmd_list() {
    check_k3d
    echo "CISC-814 k3d clusters:"
    echo ""
    k3d cluster list 2>/dev/null | head -1
    k3d cluster list 2>/dev/null | grep "${CLUSTER_PREFIX}-" || echo "(none)"
}

cmd_ensure_components() {
    local team="$1"
    local cluster_name="${CLUSTER_PREFIX}-${team}"
    local context="k3d-${cluster_name}"

    if ! kubectl --context "$context" cluster-info &>/dev/null 2>&1; then
        echo "Error: Cluster '${cluster_name}' not found."
        exit 1
    fi

    install_cluster_components "$context"
    echo "All components ready on '${cluster_name}'."
}

cmd_create_all() {
    local gpu_flag=""
    if [[ "${1:-}" == "--gpu" ]]; then
        gpu_flag="--gpu"
        shift
    fi

    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "Error: File '$file' not found."
        exit 1
    fi

    while IFS= read -r team || [[ -n "$team" ]]; do
        team=$(echo "$team" | tr -d '[:space:]')
        [[ -z "$team" || "$team" == \#* ]] && continue
        echo "--- Creating cluster for team: ${team} ---"
        cmd_create $gpu_flag "$team"
        echo ""
    done < "$file"
}

# Main
[[ $# -lt 1 ]] && usage

command="$1"
shift

case "$command" in
    create)
        [[ $# -lt 1 ]] && { echo "Error: team name required."; usage; }
        cmd_create "$@"
        ;;
    build-gpu-image)
        cmd_build_gpu_image "$@"
        ;;
    delete)
        [[ $# -lt 1 ]] && { echo "Error: team name required."; usage; }
        cmd_delete "$1"
        ;;
    info)
        [[ $# -lt 1 ]] && { echo "Error: team name required."; usage; }
        cmd_info "$1"
        ;;
    list)
        cmd_list
        ;;
    ensure-components)
        [[ $# -lt 1 ]] && { echo "Error: team name required."; usage; }
        cmd_ensure_components "$1"
        ;;
    create-all)
        [[ $# -lt 1 ]] && { echo "Error: teams file required."; usage; }
        cmd_create_all "$@"
        ;;
    *)
        echo "Error: Unknown command '${command}'"
        usage
        ;;
esac
