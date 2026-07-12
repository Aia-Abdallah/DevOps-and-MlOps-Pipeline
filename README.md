<div align="center">

# 🤖 MLOps Pipeline with LLM Serving
### CISC-814 | Queen's University | Summer 2026

[![Python](https://img.shields.io/badge/Python-3.11-blue?logo=python)](https://python.org)
[![Docker](https://img.shields.io/badge/Docker-✓-blue?logo=docker)](https://docker.com)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-k3d-326CE5?logo=kubernetes)](https://k3s.io)
[![MLflow](https://img.shields.io/badge/MLflow-Tracking-blue?logo=mlflow)](https://mlflow.org)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

**End-to-end MLOps system: LLM experimentation → quantization → A/B testing → drift monitoring → canary deployment**

[📊 MLflow](#-results) • [⚡ Quantization](#-results) • [🔀 A/B Testing](#-results) • [☸️ Kubernetes](#️-kubernetes-canary-deployment)

</div>

---

## 📋 Table of Contents
- [Overview](#-overview)
- [Architecture](#-architecture)
- [Results](#-results)
- [Screenshots](#-screenshots)
- [Tech Stack](#️-tech-stack)
- [Project Structure](#-project-structure)
- [Quick Start](#-quick-start)
- [Assignment Details](#-assignment-details)
- [Author](#-author)

---

## 🎯 Overview

A production-grade MLOps pipeline built around **Qwen2.5-1.5B** Large Language Model for sentiment analysis, featuring:

| Component | Description |
|-----------|-------------|
| 🔬 **Experimentation** | MLflow tracking with 1/3/5-shot prompting |
| ⚡ **Optimization** | GPTQ 4-bit quantization (3GB → 1.08GB) |
| 🔀 **A/B Testing** | FastAPI router with 80/20 traffic split |
| 📊 **Drift Monitoring** | Evidently AI with Prometheus metrics |
| ☸️ **Canary Deployment** | Argo Rollouts on Kubernetes (k3d) |

---

## 🏗️ Architecture

### Part A — Model Serving Architecture

[few_shot.py]  ──►  [MLflow Server]
[quantize.py]  ──►    - Experiment Tracking
[register.py]  ──►    - Model Registry
- Artifact Store

[vLLM V1: Qwen2.5-1.5B fp16 3GB ] ──── 80% ──┐
├──► [Traffic Router :8000]
[vLLM V2: Qwen2.5-1.5B GPTQ 1GB ] ──── 20% ──┘
│
▼
[Drift Detector]
│
▼
[Evidently AI :8085]


### Part B — Kubernetes Architecture
cisc814-cluster2 (k3d)
│
├── namespace: default
│   └── [Argo Rollout: sentiment-model]
│         ├── V1 pod (stable) ── 80% ──┐
│         └── V2 pod (canary) ── 20% ──┴──► [Service :8000]
│
│         Canary Steps:
│         20% ──► pause ──► 50% ──► pause ──► 80% ──► pause ──► 100% ✅
│
└── namespace: monitoring
├── Prometheus ──scrapes──► Pushgateway
├── Grafana ────queries──► Prometheus
└── Dashboard: drift score | traffic split | latency

---

## 📊 Results

### Experiment Comparison

| Model | Shots | Accuracy | F1 Score | Avg Latency |
|-------|-------|----------|----------|-------------|
| Qwen2.5-1.5B (fp16) | 1-shot | 0.90 | 0.896 | ~2.0s |
| Qwen2.5-1.5B (fp16) | 3-shot | **1.00** | **1.000** | ~3.0s |
| Qwen2.5-1.5B (fp16) | 5-shot | **1.00** | **1.000** | ~4.0s |
| Qwen2.5-1.5B (GPTQ 4-bit) | 3-shot | 0.90 | 0.896 | **0.589s** |

### A/B Testing Results

| Metric | V1 (fp16) | V2 (GPTQ 4-bit) |
|--------|-----------|-----------------|
| Requests Served | 200 | 182 |
| Avg Latency | 109.35ms | **82.8ms** |
| Model Size | 3.0 GB | **1.08 GB** |
| Drift Score | 0.0 ✅ | 0.0 ✅ |

### Quantization Impact
Model Size:   3.0GB ──▶ 1.08GB   (64% reduction 🎉)
Accuracy:     0.90  ──▶ 0.90     (no loss ✅)
Latency:      ~2.0s ──▶ 0.589s   (7x faster ⚡)

### Canary Deployment Steps
V1 Deployed (100% stable)
│
▼ Patch to V2
SetWeight: 20%  ──▶  pause
│
▼
SetWeight: 50%  ──▶  pause
│
▼
SetWeight: 80%  ──▶  pause
│
▼
V2 Promoted ✅ (100% stable)

---

## 📸 Screenshots

### 🔬 MLflow — Quantization Experiment
![MLflow Quantization](screenshots/mlflow-quantization.png)
> GPTQ 4-bit quantization run: accuracy=0.90, size=1.08GB, latency=0.589s, method=gptq

---

### ⚡ vLLM — Live Model Serving
![vLLM Serving](screenshots/vllm-serving.png)
> Qwen2.5-1.5B served via vLLM with successful HTTP 200 sentiment prediction response

---

### 🔄 ArgoCD — GitOps Deployment Tree
![ArgoCD Tree](screenshots/argocd-tree.png)
> ArgoCD: Healthy ✅ | Synced ✅ | Auto-sync enabled | Full resource tree visible

---

### 📊 Grafana — Monitoring Dashboard
![Grafana Dashboard](screenshots/grafana-dashboard.png)
> Real-time metrics: Request Rate | Error Rate | Latency (p50/p95/p99) | CPU | Memory

---

### 🎯 Prometheus — Service Monitor Targets
![Prometheus Targets](screenshots/prometheus-targets.png)
> ServiceMonitor scraping 3/3 targets UP ✅ — all sentiment app pods monitored

---

## 🛠️ Tech Stack

| Category | Tools |
|----------|-------|
| **LLM Serving** | Qwen2.5-1.5B, vLLM |
| **Quantization** | GPTQ 4-bit (GPTQModel) |
| **Experiment Tracking** | MLflow |
| **API Framework** | FastAPI, Uvicorn |
| **Drift Detection** | Evidently AI |
| **Containerization** | Docker |
| **Orchestration** | Kubernetes (k3d) |
| **Canary Deployment** | Argo Rollouts |
| **GitOps** | ArgoCD |
| **Monitoring** | Prometheus, Grafana |
| **CI/CD** | Gitea Actions |
| **Container Registry** | Docker Registry |

---

## 📁 Project Structure

```
DevOps-and-MlOps-Pipeline/
│
├── screenshots/
│   ├── mlflow-quantization.png
│   ├── vllm-serving.png
│   ├── argocd-tree.png
│   ├── grafana-dashboard.png
│   └── prometheus-targets.png
│
├── assignment-2-mlops-pipeline/
│   └── starter/ml-sentiment-app/
│       ├── training/
│       │   ├── src/
│       │   │   ├── train.py
│       │   │   ├── registration.py
│       │   │   └── experiments/
│       │   │       └── few_shot.py
│       │   └── configs/
│       │       └── experiment_config.yaml
│       ├── quantization/
│       │   └── quantize_model.py
│       ├── serving/
│       │   ├── traffic_router.py
│       │   ├── predictions.jsonl
│       │   ├── v1_predictions.jsonl
│       │   └── v2_predictions.jsonl
│       ├── monitoring/
│       │   ├── drift_detector.py
│       │   ├── send_predictions.py
│       │   └── drift_report.html
│       ├── k8s/
│       │   ├── rollout.yaml
│       │   ├── analysis-template.yaml
│       │   ├── service.yaml
│       │   └── configmap.yaml
│       └── data/
│           ├── train_sentiment.csv
│           └── eval_sentiment.csv
│
└── infrastructure/
    ├── k3d/
    ├── gitea/
    └── otel/
```

## 🚀 Quick Start

### Prerequisites

```bash
docker --version        # Docker 20+
kubectl version         # kubectl 1.28+
k3d --version           # k3d 5+
helm version            # Helm 3+
python3 --version       # Python 3.11+

1. Start MLflow Server
mlflow server \
  --backend-store-uri postgresql://mlflow:mlflow@localhost:5432/mlflow \
  --default-artifact-root mlflow-artifacts:/ \
  --host 0.0.0.0 --port 5050
# UI: http://localhost:5050
2. Run Few-Shot Experiments
cd training
source venv/bin/activate
python src/experiments/few_shot.py
# Runs: 1-shot (acc=0.90) | 3-shot (acc=1.0) | 5-shot (acc=1.0)
3. Quantize Model (GPTQ 4-bit)
cd quantization
source ../venv-quantization/bin/activate
python quantize_model.py
# Output: ./qwen2.5-1.5b-gptq-4bit/ (1.08GB)

4. Register Models
cd training
python src/registration.py
# champion:   Qwen2.5-1.5B fp16
# challenger: Qwen2.5-1.5B GPTQ 4-bit

5. Start A/B Traffic Router
cd serving
uvicorn traffic_router:app --host 0.0.0.0 --port 8000

# Test prediction
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"text": "This product is amazing!"}'

# Check stats
curl http://localhost:8000/stats
6. Run Drift Detection
cd monitoring
python drift_detector.py
# Report: monitoring/drift_report.html
# UI:     http://localhost:8085
7. Deploy to Kubernetes
# Create k3d cluster
k3d cluster create cisc814-cluster2

# Install Argo Rollouts
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts \
  -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# Apply manifests
kubectl apply -f k8s/

# Watch V1 rollout
kubectl argo rollouts get rollout sentiment-model --watch

# Trigger canary V1 → V2
kubectl argo rollouts set image sentiment-model \
  sentiment=localhost:5001/sentiment-mock:v2

# Promote through steps
kubectl argo rollouts promote sentiment-model

Key Learnings
Quantization can dramatically reduce serving costs with minimal accuracy loss

A/B testing reveals real production differences invisible in offline evaluation

Canary deployments make production changes safe and reversible

✅ 100% accuracy with 3-shot prompting
✅ 64% model size reduction via GPTQ
✅ 7x faster inference after quantization
✅ Zero drift detected between V1 and V2
✅ Successful canary: 20% → 50% → 80% → 100%
✅ ArgoCD: Healthy + Synced
✅ Prometheus: 3/3 targets UP


Drift monitoring is essential for LLM reliability in production


👩‍💻 Author
Aya Abdallah
Mechatronics Engineering
Queen's University — CISC-814, Summer 2026

GitHub

