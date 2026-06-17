"""Model registration: wraps MMT models as CustomModel for Model Registry."""
import json
import pickle
import tempfile
from typing import Dict, Any
import pandas as pd
from snowflake.ml.model import custom_model, model_signature
from snowflake.ml.registry import Registry
from snowflake.snowpark import Session
try:
    from utils import (
        get_feature_config, create_session, get_fully_qualified_name
    )
except ImportError:
    from .utils import (
        get_feature_config, create_session, get_fully_qualified_name
    )

feature_cfg = get_feature_config()

GRAIN = feature_cfg["partition_col"]
TARGET = feature_cfg["target_col"]
TIME = feature_cfg["time_col"]
EXCLUDE_COLS = [GRAIN, TARGET, TIME]

class MMTDemandModel(custom_model.CustomModel):
    """CustomModel wrapper with @partitioned_api for distributed inference."""
    
    def __init__(self, context: custom_model.ModelContext) -> None:
        super().__init__(context)
        self._model_cache: Dict[str, Any] = {}
        self._stage_paths: Dict[str, str] = {}
        
        try:
            manifest_path = context["model_manifest"]
            with open(manifest_path, "r") as f:
                self._stage_paths = json.load(f)
        except (KeyError, FileNotFoundError, json.JSONDecodeError):
            pass
    
    def _get_model(self, partition_key: str) -> Any:
        """Load and cache model for a partition from stage."""
        if partition_key not in self._model_cache:
            stage_path = self._stage_paths.get(partition_key)
            if stage_path is None:
                return None
            
            model_path = f"{stage_path}/model.pkl"
            from snowflake.snowpark.files import SnowflakeFile
            with SnowflakeFile.open(model_path, "rb", require_scoped_url=False) as f:
                self._model_cache[partition_key] = pickle.load(f)
        
        return self._model_cache.get(partition_key)
    
    @custom_model.partitioned_api
    def predict(self, input_df: pd.DataFrame) -> pd.DataFrame:
        """Generate predictions for a single partition's data."""
        import numpy as np
        
        partition_key = input_df[GRAIN].iloc[0]
        
        model = self._get_model(partition_key)
        if model is None:
            raise ValueError(f"No model found for partition: {partition_key}")
        
        feature_cols = [c for c in input_df.columns if c not in EXCLUDE_COLS]
        X = input_df[feature_cols].astype("float32")
        preds = model.predict(X)
        
        return pd.DataFrame({
            f"OUTPUT_{GRAIN}": input_df[GRAIN].values,
            f"OUTPUT_{TIME}": input_df[TIME].values,
            f"PRED_{TARGET}": preds,
        })


def create_sample_input(session: Session) -> pd.DataFrame:
    """Sample 100 rows from TRAIN_DATA for schema inference.
    
    Uses TRAIN_DATA (not FEATURE_TABLE) because the model signature must match
    the actual features used during training, which may be a subset of all available features.
    """
    sample_df = session.sql("""
        SELECT *
        FROM TRAIN_DATA
        LIMIT 100
    """).to_pandas()
    
    keep_cols = [c for c in sample_df.columns if c != TARGET]
    sample_df = sample_df[keep_cols]
    
    if TIME in sample_df.columns:
        sample_df[TIME] = pd.to_datetime(sample_df[TIME])
    
    return sample_df


def build_stage_paths(session: Session) -> Dict[str, str]:
    """Return dict mapping partition_id -> stage_path from MODEL_CATALOG."""
    catalog_fqn = get_fully_qualified_name("MODEL_CATALOG")    
    return {row.PARTITION_ID:row.STAGE_PATH for row in session.table(catalog_fqn).collect()}


def register_model(session: Session = None, model_name: str = "MMT_DEMAND_MODEL"):
    """Log partitioned model to Snowflake Model Registry with test prediction."""
    if session is None:
        session = create_session()
        print(f"Connected: {session.get_current_account()}")
    
    print(f"\n   Registering Partitioned Model to Snowflake Model Registry")
    
    reg = Registry(
        session=session,
        database_name=session.get_current_database(),
        schema_name=session.get_current_schema(),
    )
    
    stage_paths = build_stage_paths(session)
    print(f"   Found {len(stage_paths)} active models")

    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump(stage_paths, f)
        manifest_path = f.name
    
    model_context = custom_model.ModelContext(
        artifacts={"model_manifest": manifest_path}
    )
    wrapper = MMTDemandModel(model_context)
    
    sample_input = create_sample_input(session)
    print(f"   Sample input shape: {sample_input.shape}")
    
    input_features = []
    for col in sample_input.columns:
        if col == GRAIN:
            input_features.append(model_signature.FeatureSpec(name=col, dtype=model_signature.DataType.STRING))
        elif col == TIME:
            input_features.append(model_signature.FeatureSpec(name=col, dtype=model_signature.DataType.TIMESTAMP_NTZ))
        else:
            input_features.append(model_signature.FeatureSpec(name=col, dtype=model_signature.DataType.FLOAT))
    
    output_features = [
        model_signature.FeatureSpec(name=f"OUTPUT_{GRAIN}", dtype=model_signature.DataType.STRING),
        model_signature.FeatureSpec(name=f"OUTPUT_{TIME}", dtype=model_signature.DataType.TIMESTAMP_NTZ),
        model_signature.FeatureSpec(name=f"PRED_{TARGET}", dtype=model_signature.DataType.FLOAT),
    ]
    
    sig = model_signature.ModelSignature(inputs=input_features, outputs=output_features)
    
    print(f"\n   Logging partitioned model to registry...")
    
    mv = reg.log_model(
        wrapper,
        model_name=model_name,
        signatures={"predict": sig},
        options={"function_type": "TABLE_FUNCTION"},
        conda_dependencies=["xgboost", "pandas", "numpy"],
        target_platforms=["WAREHOUSE","SNOWPARK_CONTAINER_SERVICES"],
    )
    
    model = reg.get_model(model_name)
    model.default = mv.version_name
    
    print(f"\n Model registered successfully!")
    print(f"   Model: {mv.model_name}")
    print(f"   Version: {mv.version_name} (set as default)")
    print(f"   Database: {session.get_current_database()}")
    print(f"   Schema: {session.get_current_schema()}")
    
    print(f"\n Available methods:")
    print(mv.show_functions())
    
    return mv


if __name__ == "__main__":
    
    register_model()
