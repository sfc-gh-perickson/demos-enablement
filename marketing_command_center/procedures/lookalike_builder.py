"""
Lookalike Audience Builder Stored Procedure

Registered as: SB_COMMAND_CENTER.PROCEDURES.BUILD_LOOKALIKE

Accepts seed customer IDs, trains a classifier to distinguish them from non-seed,
then scores the full customer base to find lookalikes.
"""

from snowflake.snowpark import Session
from snowflake.snowpark.types import ArrayType, StringType, VariantType
import snowflake.snowpark.functions as F


def build_lookalike(
    session: Session,
    seed_customer_ids: list,
    feature_view_names: list,
    model_name: str,
) -> str:
    """
    Build a lookalike model from seed customers.

    Args:
        session: Snowpark session
        seed_customer_ids: List of customer IDs to use as positive class
        feature_view_names: List of feature view names to pull features from
        model_name: Name to register the model under in the registry

    Returns:
        JSON string with model metrics and top lookalike customer IDs
    """
    import json
    import numpy as np
    import pandas as pd
    from xgboost import XGBClassifier
    from sklearn.model_selection import cross_val_score
    from sklearn.metrics import roc_auc_score
    from snowflake.ml.feature_store import FeatureStore
    from snowflake.ml.registry import Registry

    # Set database context (needed for EXECUTE AS CALLER via SQL API)
    session.sql("USE DATABASE SB_COMMAND_CENTER").collect()
    session.sql("USE SCHEMA FEATURE_STORE").collect()
    session.sql("USE WAREHOUSE COMPUTE_WH").collect()

    # Connect to Feature Store
    fs = FeatureStore(
        session=session,
        database='SB_COMMAND_CENTER',
        name='FEATURE_STORE',
        default_warehouse='COMPUTE_WH'
    )

    # Get all customers
    all_customers = session.sql(
        "SELECT DISTINCT CUSTOMER_ID FROM SB_COMMAND_CENTER.RAW.CUSTOMER_TRANSACTIONS"
    )
    all_customer_list = [row['CUSTOMER_ID'] for row in all_customers.collect()]

    # Get feature views
    feature_views = []
    for fv_name in feature_view_names:
        fv = fs.get_feature_view(fv_name, 'v1')
        feature_views.append(fv)

    # Retrieve features for all customers
    feature_data = fs.retrieve_feature_values(
        spine_df=all_customers,
        features=feature_views
    )
    features_pdf = feature_data.to_pandas()

    # Create labels: 1 = seed customer, 0 = non-seed
    seed_set = set(seed_customer_ids)
    features_pdf['IS_SEED'] = features_pdf['CUSTOMER_ID'].apply(
        lambda x: 1 if x in seed_set else 0
    )

    # Determine feature columns (exclude CUSTOMER_ID and IS_SEED)
    feature_cols = [c for c in features_pdf.columns
                    if c not in ('CUSTOMER_ID', 'IS_SEED', 'GEOGRAPHY_STATE', 'GEOGRAPHY_COUNTRY')]
    features_pdf[feature_cols] = features_pdf[feature_cols].fillna(0)

    X = features_pdf[feature_cols].values
    y = features_pdf['IS_SEED'].values

    # Subsample non-seed to balance classes (max 5:1 ratio)
    seed_count = int(y.sum())
    non_seed_idx = np.where(y == 0)[0]
    max_non_seed = min(len(non_seed_idx), seed_count * 5)
    sampled_non_seed = np.random.choice(non_seed_idx, size=max_non_seed, replace=False)
    seed_idx = np.where(y == 1)[0]
    train_idx = np.concatenate([seed_idx, sampled_non_seed])

    X_train = X[train_idx]
    y_train = y[train_idx]

    # Train XGBClassifier with cross-validation
    model = XGBClassifier(
        n_estimators=150, max_depth=5, learning_rate=0.1,
        scale_pos_weight=max_non_seed / max(seed_count, 1),
        eval_metric='auc', random_state=42
    )

    # Cross-validation AUC
    cv_scores = cross_val_score(model, X_train, y_train, cv=3, scoring='roc_auc')
    avg_auc = float(np.mean(cv_scores))

    # Final fit on all training data
    model.fit(X_train, y_train)

    # Log to Model Registry
    reg = Registry(session, database_name='SB_COMMAND_CENTER', schema_name='REGISTRY')
    sample_input = pd.DataFrame([dict(zip(feature_cols, X_train[0]))])

    reg.log_model(
        model,
        model_name=model_name,
        version_name='v1',
        metrics={'auc': avg_auc, 'seed_count': seed_count, 'features_used': len(feature_cols)},
        sample_input_data=sample_input
    )

    # Score full customer base
    all_scores = model.predict_proba(X)[:, 1]
    features_pdf['LOOKALIKE_SCORE'] = all_scores

    # Feature importances
    feature_importances = sorted(
        [{'feature': name, 'importance': float(score)}
         for name, score in zip(feature_cols, model.feature_importances_)],
        key=lambda x: -x['importance']
    )

    # Score distribution histogram (non-seed only)
    non_seed_scores = all_scores[y == 0]
    hist_counts, _ = np.histogram(non_seed_scores, bins=10, range=(0, 1))
    score_distribution = [
        {'bucket': f'{i/10:.1f}-{(i+1)/10:.1f}', 'count': int(count)}
        for i, count in enumerate(hist_counts)
    ]

    # Get top 25 non-seed lookalikes
    non_seed_results = features_pdf[features_pdf['IS_SEED'] == 0].nlargest(1000, 'LOOKALIKE_SCORE')
    top_lookalikes = [
        {'customer_id': row['CUSTOMER_ID'], 'score': round(float(row['LOOKALIKE_SCORE']), 4)}
        for _, row in non_seed_results.head(25).iterrows()
    ]

    # Write scores to a results table
    output_df = features_pdf[['CUSTOMER_ID', 'LOOKALIKE_SCORE', 'IS_SEED']].copy()
    output_df['MODEL_NAME'] = model_name
    output_sdf = session.create_dataframe(output_df)
    output_sdf.write.mode('overwrite').save_as_table(
        f'SB_COMMAND_CENTER.SCORING.LOOKALIKE_{model_name.upper()}'
    )

    result = {
        'model_name': model_name,
        'auc': avg_auc,
        'cv_fold_scores': cv_scores.tolist(),
        'seed_count': seed_count,
        'total_scored': len(features_pdf),
        'feature_importances': feature_importances,
        'score_distribution': score_distribution,
        'top_lookalikes': top_lookalikes,
    }

    return json.dumps(result)


# Registration SQL (run separately to register the procedure):
#
# CREATE OR REPLACE PROCEDURE SB_COMMAND_CENTER.PROCEDURES.BUILD_LOOKALIKE(
#     SEED_CUSTOMER_IDS ARRAY,
#     FEATURE_VIEW_NAMES ARRAY,
#     MODEL_NAME VARCHAR
# )
# RETURNS VARCHAR
# LANGUAGE PYTHON
# RUNTIME_VERSION = '3.10'
# PACKAGES = ('snowflake-snowpark-python', 'snowflake-ml-python', 'xgboost', 'scikit-learn', 'pandas', 'numpy')
# HANDLER = 'build_lookalike'
# IMPORTS = ('@SB_COMMAND_CENTER.PROCEDURES.PROC_STAGE/lookalike_builder.py')
# EXECUTE AS CALLER;
