"""Register the best model of a given experiment type in the MLflow Model Registry."""

from __future__ import annotations

import argparse

import mlflow
import yaml


def load_config(config_path: str = "configs/experiment_config.yaml") -> dict:
    with open(config_path) as f:
        return yaml.safe_load(f)


def register_model(
    tracking_uri: str,
    experiment_name: str,
    experiment_type: str,
    alias: str,
) -> None:
    """Register the best run of a given experiment type under the given alias."""
    mlflow.set_tracking_uri(tracking_uri)
    client = mlflow.tracking.MlflowClient()

    # 1. Get experiment
    experiment = client.get_experiment_by_name(experiment_name)
    if experiment is None:
        raise ValueError(f"Experiment '{experiment_name}' not found")

    print(f"Found experiment: {experiment_name} (id={experiment.experiment_id})")

    # 2. Search for best run by F1 score
    runs = client.search_runs(
        experiment_ids=[experiment.experiment_id],
        filter_string=f"params.experiment_type = '{experiment_type}'",
        order_by=["metrics.f1_macro DESC"],
        max_results=1
    )

    if not runs:
        raise ValueError(f"No runs found with experiment_type='{experiment_type}'")

    best_run = runs[0]
    run_id = best_run.info.run_id
    vllm_model_path = best_run.data.params.get("vllm_model_path", "")
    f1_score = best_run.data.metrics.get("f1_macro", 0)

    print(f"Best run ID: {run_id}")
    print(f"F1 score: {f1_score:.3f}")
    print(f"vllm_model_path: {vllm_model_path}")

    # 3. Model name in registry
    model_name = "sentiment-qwen2.5"

    # 4. Create registered model if it doesn't exist
    try:
        client.create_registered_model(model_name)
        print(f"Created registered model: {model_name}")
    except Exception:
        print(f"Registered model '{model_name}' already exists")

    # 5. Create model version
    try:
        model_version = client.create_model_version(
            name=model_name,
            source=f"runs:/{run_id}/model",
            run_id=run_id,
            description=f"Best {experiment_type} run with F1={f1_score:.3f}"
        )
    except Exception:
        model_version = client.create_model_version(
            name=model_name,
            source=f"runs:/{run_id}",
            run_id=run_id,
            description=f"Best {experiment_type} run with F1={f1_score:.3f}"
        )

    version_number = model_version.version
    print(f"Created model version: {version_number}")

    # 6. Set alias (champion or challenger)
    client.set_registered_model_alias(
        name=model_name,
        alias=alias,
        version=version_number
    )
    print(f"Set alias '{alias}' to version {version_number}")

    # 7. Set vllm_model_path tag
    client.set_model_version_tag(
        name=model_name,
        version=version_number,
        key="vllm_model_path",
        value=vllm_model_path
    )
    print(f"Set tag 'vllm_model_path' = '{vllm_model_path}'")
    print("Done! ✅")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Register a model in MLflow Model Registry")
    parser.add_argument("--tracking-uri", required=True, help="MLflow tracking URI")
    parser.add_argument("--experiment-name", required=True, help="MLflow experiment name")
    parser.add_argument("--experiment-type", required=True, help="Value of params.experiment_type to filter on")
    parser.add_argument("--alias", required=True, help="Model alias to assign (e.g. champion, challenger)")
    args = parser.parse_args()

    register_model(args.tracking_uri, args.experiment_name, args.experiment_type, args.alias)