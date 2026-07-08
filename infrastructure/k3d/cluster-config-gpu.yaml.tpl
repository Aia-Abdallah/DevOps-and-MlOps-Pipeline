apiVersion: k3d.io/v1alpha5
kind: Simple
metadata:
  name: cisc814-TEAM_NAME
servers: 1
agents: 0
image: K3S_IMAGE
network: cisc814-network
registries:
  config: |
    mirrors:
      "registry.local:5000":
        endpoint:
          - "http://cisc814-registry:5000"
ports:
  - port: ARGOCD_PORT:30080/tcp
    nodeFilters:
      - server:*
  - port: GRAFANA_PORT:30081/tcp
    nodeFilters:
      - server:*
  - port: PROMETHEUS_PORT:30090/tcp
    nodeFilters:
      - server:*
options:
  k3s:
    extraArgs:
      - arg: --disable=traefik
        nodeFilters:
          - server:*
  runtime:
    gpuRequest: all
    serversMemory: ""
    agentsMemory: ""
