<div align="center">

# 🤖 MLOps Pipeline with LLM Serving
### CISC-814 | Queen's University | Summer 2026

[![Python](https://img.shields.io/badge/Python-3.11-blue?logo=python)](https://python.org)
[![Docker](https://img.shields.io/badge/Docker-✓-blue?logo=docker)](https://docker.com)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-k3d-326CE5?logo=kubernetes)](https://k3s.io)
[![MLflow](https://img.shields.io/badge/MLflow-Tracking-blue?logo=mlflow)](https://mlflow.org)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

**End-to-end MLOps system: LLM experimentation → quantization → A/B testing → drift monitoring → canary deployment**

[📊 MLflow](#-experiment-tracking) • [⚡ Quantization](#-quantization) • [🔀 A/B Testing](#-ab-testing) • [☸️ Kubernetes](#️-kubernetes-canary-deployment)

</div>

---

## 📋 Table of Contents
- [Overview](#-overview)
- [Architecture](#-architecture)
- [Results](#-results)
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

##  Architecture

### Part A — Model Serving Architecture

┌─────────────────────────────────────────────────────┐
│                    Local Machine                     │
│                                                      │
│  ┌──────────────┐      ┌─────────────────────────┐  │
│  │ few_shot.py  │─────▶│     MLflow Server        │  │
│  │ quantize.py  │─────▶│  • Experiment Tracking   │  │
│  │registration.py│────▶│  • Model Registry        │  │
│  └──────────────┘      │  • Artifact Store        │  │
│                         └─────────────────────────┘  │
│                                                      │
│  ┌─────────────┐        ┌──────────────────────┐     │
│  │ vLLM V1     │        │ vLLM V2 (GPTQ 4-bit) │     │
│  │ Qwen2.5-1.5B│        │ Qwen2.5-1.5B-GPTQ    │     │
│  │ fp16 3GB   │        │ 4-bit 1.08GB          │     │
│  └──────┬──────┘        └──────────┬───────────┘     │
│         │     80%  |  20%          │                 │
│         └──────────┼───────────────┘                 │
│                ┌───▼────┐                            │
│                │ Traffic │ :8000                     │
│                │ Router  │ FastAPI                   │
│                └───┬─────┘                           │
│                    │ predictions.jsonl               │
│                ┌───▼──────────┐                      │
│                │Drift Detector│──▶ Evidently :8085   │
│                └──────────────┘                      │
└───────────────────────────────────────────────────── ┘

shell

### Part B — Kubernetes Architecture

┌────────────────────────────────────────────────────────┐
│                 cisc814-cluster2 (k3d)                 │
│                                                        │
│  namespace: default                                    │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Argo Rollout: sentiment-model                   │  │
│  │                                                  │  │
│  │  [stable: V1]──80%──┐                            │  │
│  │  [canary: V2]──20%──┴──▶ Service :8000           │  │
│  │                                                  │  │
│  │  Canary Steps:                                   │  │
│  │  20% → pause → 50% → pause → 80% → pause → 100%  │  
│  └──────────────────────────────────────────────────┘  │
│                                                        │
│  namespace: monitoring                                 │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Prometheus ──scrapes── Pushgateway              │  │
│  │  Grafana    ──queries──▶ Prometheus              │  │
│  │  Dashboard: drift score, traffic, latency        │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────┘

yaml

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

shell

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

yaml

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
| **Monitoring** | Prometheus, Grafana |
| **CI/CD** | Gitea Actions, ArgoCD |
| **Container Registry** | Docker Registry |

---

## 📁 Project Structure

├── assignment-2-mlops-pipeline/
│   └── starter/ml-sentiment-app/
│       ├── training/
│       │   ├── src/
│       │   │   ├── train.py                  # MLflow setup
│       │   │   ├── experiments/
│       │   │   │   └── few_shot.py           # 1/3/5-shot experiments
│       │   │   └── registration.py           # Model Registry
│       │   └── configs/
│       │       └── experiment_config.yaml
│       ├── quantization/
│       │   └── quantize_model.py             # GPTQ 4-bit quantization
│       ├── serving/
│       │   ├── traffic_router.py             # FastAPI A/B router
│       │   ├── predictions.jsonl             # All predictions log
│       │   ├── v1_predictions.jsonl          # V1 logs
│       │   └── v2_predictions.jsonl          # V2 logs
│       ├── monitoring/
│       │   ├── drift_detector.py             # Evidently AI drift
│       │   ├── send_predictions.py           # Push to Evidently UI
│       │   └── drift_report.html             # Generated report
│       ├── k8s/
│       │   ├── rollout.yaml                  # Argo Rollouts config
│       │   ├── analysis-template.yaml        # Drift analysis job
│       │   ├── service.yaml                  # Kubernetes service
│       │   └── configmap.yaml                # App configuration
│       └── data/
│           ├── train_sentiment.csv           # 200 training samples
│           └── eval_sentiment.csv            # 100 eval samples
└── infrastructure/
├── k3d/                                  # Cluster configs
├── gitea/                                # CI/CD server
└── otel/                                 # Observability

yaml

---

## 🚀 Quick Start

### Prerequisites

```bash
docker --version        # Docker 20+
kubectl version         # kubectl 1.28+
k3d --version           # k3d 5+
helm version            # Helm 3+
python3 --version       # Python 3.11+

1. Start MLflow Server

bash
mlflow server \
  --backend-store-uri postgresql://mlflow:mlflow@localhost:5432/mlflow \
  --default-artifact-root mlflow-artifacts:/ \
  --host 0.0.0.0 --port 5050

# UI: http://localhost:5050

2. Run Few-Shot Experiments

bash
cd training
source venv/bin/activate
python src/experiments/few_shot.py

# Runs: 1-shot (acc=0.90) | 3-shot (acc=1.0) | 5-shot (acc=1.0)

3. Quantize Model (GPTQ 4-bit)

bash
cd quantization
source ../venv-quantization/bin/activate
python quantize_model.py

# Output: ./qwen2.5-1.5b-gptq-4bit/ (1.08GB)

4. Register Models

bash
cd training
python src/registration.py

# champion:   Qwen2.5-1.5B fp16
# challenger: Qwen2.5-1.5B GPTQ 4-bit

5. Start A/B Traffic Router

bash
cd serving
uvicorn traffic_router:app --host 0.0.0.0 --port 8000

# Test prediction
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"text": "This product is amazing!"}'

# Check stats
curl http://localhost:8000/stats

6. Run Drift Detection

bash
cd monitoring
python drift_detector.py

# Report: monitoring/drift_report.html
# UI:     http://localhost:8085

7. Deploy to Kubernetes

bash
# Create k3d cluster
k3d cluster create cisc814-cluster2

# Install Argo Rollouts
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts \
  -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# Apply manifests
kubectl apply -f k8s/

# Watch initial V1 rollout
kubectl argo rollouts get rollout sentiment-model --watch

# Trigger canary (V1 → V2)
kubectl argo rollouts set image sentiment-model \
  sentiment=localhost:5001/sentiment-mock:v2

# Promote through steps
kubectl argo rollouts promote sentiment-model

📚 Assignment Details
Part A — MLflow Experimentation ✅

    Task 1: MLflow Setup & Configuration
    Task 2: Few-Shot Experiments (1/3/5-shot with Qwen2.5-1.5B)
    Task 3: GPTQ 4-bit Quantization (64% size reduction)
    Task 4: Model Registry (champion fp16 + challenger GPTQ)

Part B — Production MLOps ✅

    Task 1: Model Serving with vLLM (V1 fp16 + V2 GPTQ)
    Task 2: A/B Testing (80/20 traffic split, 382 predictions)
    Task 3: Drift Monitoring (Evidently AI, drift score = 0.0)
    Task 4: k3d + Argo Rollouts Canary Deployment (6 steps)
    Task 5: Report + Video Demo
