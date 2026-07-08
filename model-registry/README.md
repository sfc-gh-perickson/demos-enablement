# Snowflake Model Registry Demo

Upload a pre-trained XGBoost model artifact (pickle) to Snowflake's Model Registry and run inference from it.

## Setup

```bash
pip install -r requirements.txt
```

## Usage

### 1. Train and save the model

```bash
python train_model.py
```

This trains an XGBoost classifier on sklearn's breast cancer dataset and saves it to `model_artifact/xgboost_model.pkl`.

### 2. Register the model in Snowflake

Open `register_model.ipynb` and fill in your Snowflake connection parameters in the first cell. Then run all cells.

The notebook:
1. Connects to Snowflake
2. Creates the `ML_REGISTRY_DEMO.REGISTRY` database and schema
3. Loads the pickle file from disk
4. Registers the model via `snowflake-ml-python`
5. Runs inference on sample data through the registered model
6. Lists all models in the registry

## Snowflake Resources

- Database: `ML_REGISTRY_DEMO`
- Schema: `ML_REGISTRY_DEMO.REGISTRY`

## What's Happening Under the Hood

When you call `reg.log_model()`, Snowflake:
- Serializes the model and its dependencies
- Uploads them as a model object in the specified schema
- Exposes inference methods (like `predict`) as callable functions
- Tracks versioning, metadata, and metrics

You can then call `mv.run(df)` to run predictions directly in Snowflake without moving data out.
