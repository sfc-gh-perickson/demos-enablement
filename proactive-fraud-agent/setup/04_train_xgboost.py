"""
04_train_xgboost.py — XGBoost + SHAP + Model Registry
REDESIGNED: Regularized model with label noise and calibration for realistic
probability distribution (no more perfect separation).
"""

import json
import numpy as np
import pandas as pd
from snowflake.snowpark import Session
from snowflake.snowpark import functions as F
from snowflake.ml.registry import Registry
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.calibration import CalibratedClassifierCV
from sklearn.metrics import classification_report, roc_auc_score
from sklearn.model_selection import train_test_split
import shap

# Connect
session = Session.builder.config("connection_name", "parker_demo").create()
session.sql("USE DATABASE FRAUD_DETECTION_DEMO").collect()
session.sql("USE WAREHOUSE FRAUD_DEMO_WH").collect()

# Pull feature data
print("Loading feature data...")
features_df = session.table('FEATURES."FRAUD_FEATURES$V1"').to_pandas()
print(f"Total samples: {len(features_df)}")
print(f"Fraud labels: {features_df['IS_FRAUD_LABEL'].value_counts().to_dict()}")

# Define feature columns (expanded set)
FEATURE_COLS = [
    "VELOCITY_1H", "VELOCITY_24H", "VELOCITY_7D", "VELOCITY_30D",
    "VELOCITY_CHANGE_RATIO",
    "TOTAL_AMOUNT_24H", "AVG_AMOUNT_7D", "MAX_AMOUNT_7D", "AMOUNT_STDDEV_7D",
    "MAX_TO_AVG_RATIO_7D",
    "UNIQUE_MERCHANTS_7D", "NEW_MERCHANT_RATIO_7D",
    "PCT_HIGH_RISK_MERCHANT_7D", "PCT_NEW_MERCHANTS_7D",
    "GEO_SPREAD_24H", "AVG_DISTANCE_FROM_HOME_7D",
    "PCT_INTERNATIONAL_7D", "DISTINCT_CURRENCIES_7D",
    "PCT_NIGHT_TXNS_7D", "PCT_WEEKEND_7D",
    "CHANNEL_DIVERSITY_7D", "DEVICE_SWITCH_COUNT_24H",
    "REFUND_TO_PURCHASE_RATIO_7D",
    "MAX_AMOUNT_TO_CREDIT_RATIO_7D",
    "DORMANCY_DAYS_BEFORE_CURRENT",
]
LABEL_COL = "IS_FRAUD_LABEL"

# Clean up features
for col in FEATURE_COLS:
    if col in features_df.columns:
        features_df[col] = pd.to_numeric(features_df[col], errors="coerce").fillna(0)
    else:
        print(f"  WARNING: {col} not found in data, filling with 0")
        features_df[col] = 0

features_df[LABEL_COL] = features_df[LABEL_COL].astype(int)

# Available features (drop any missing)
available_features = [c for c in FEATURE_COLS if c in features_df.columns]
print(f"\nUsing {len(available_features)} features")

# =============================================================================
# LABEL NOISE: Flip 15% of fraud labels → creates model uncertainty
# This simulates real-world label inaccuracy (not all flagged txns are actually fraud,
# and some fraud slips through undetected)
# =============================================================================
print("\nApplying label noise (15% flip rate on positives)...")
np.random.seed(42)
fraud_mask = features_df[LABEL_COL] == 1
n_fraud = fraud_mask.sum()
flip_indices = np.random.choice(
    features_df[fraud_mask].index,
    size=int(n_fraud * 0.15),
    replace=False
)
features_df.loc[flip_indices, LABEL_COL] = 0
print(f"  Flipped {len(flip_indices)} fraud labels to non-fraud")
print(f"  New distribution: {features_df[LABEL_COL].value_counts().to_dict()}")

# =============================================================================
# TRAIN/TEST SPLIT
# =============================================================================
train_df, test_df = train_test_split(
    features_df, test_size=0.25, random_state=42, stratify=features_df[LABEL_COL]
)
print(f"\nTrain: {len(train_df)}, Test: {len(test_df)}")

X_train = train_df[available_features].values
y_train = train_df[LABEL_COL].values
X_test = test_df[available_features].values
y_test = test_df[LABEL_COL].values

# =============================================================================
# TRAIN: Heavily regularized GradientBoosting (prevents overfitting)
# =============================================================================
print("\nTraining regularized GradientBoostingClassifier...")
base_model = GradientBoostingClassifier(
    n_estimators=100,       # fewer trees
    max_depth=3,            # shallow trees (was 5)
    learning_rate=0.05,     # slower learning (was 0.1)
    subsample=0.7,          # more randomness (was 0.8)
    min_samples_leaf=50,    # minimum samples per leaf (prevents memorization)
    min_samples_split=100,  # minimum samples to split
    max_features=0.6,       # feature subsampling
    random_state=42,
)
base_model.fit(X_train, y_train)

# =============================================================================
# CALIBRATION: Platt scaling to get realistic probability estimates
# =============================================================================
print("Calibrating probabilities (Platt scaling)...")
model = CalibratedClassifierCV(base_model, method='sigmoid', cv=5)
model.fit(X_train, y_train)

# Evaluate
y_pred = model.predict(X_test)
y_prob = model.predict_proba(X_test)[:, 1]

print("\n--- Classification Report ---")
print(classification_report(y_test, y_pred, target_names=["Legit", "Fraud"]))

auc = roc_auc_score(y_test, y_prob)
print(f"ROC AUC: {auc:.4f}")

# Show probability distribution
print("\n--- Probability Distribution ---")
bins = [0, 0.2, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
all_probs = model.predict_proba(features_df[available_features].values)[:, 1]
for i in range(len(bins)-1):
    count = ((all_probs >= bins[i]) & (all_probs < bins[i+1])).sum()
    print(f"  {bins[i]:.1f}-{bins[i+1]:.1f}: {count} customers")

features_df["FRAUD_PROBABILITY"] = all_probs

# =============================================================================
# SHAP: Use the base model (TreeExplainer doesn't work on calibrated wrapper)
# =============================================================================
print("\nComputing SHAP values...")
explainer = shap.TreeExplainer(base_model)
X_all = features_df[available_features].values.astype(np.float64)
shap_values = explainer.shap_values(X_all)

# Build SHAP summary: top 5 factors per customer
print("Building SHAP summary...")
shap_records = []
for i in range(len(features_df)):
    customer_id = features_df.iloc[i]["CUSTOMER_ID"]
    fraud_prob = float(features_df.iloc[i]["FRAUD_PROBABILITY"])
    sv = shap_values[i]

    # Top 5 by absolute value
    top_indices = np.argsort(np.abs(sv))[-5:][::-1]
    top_factors = []
    for idx in top_indices:
        if abs(sv[idx]) > 0.001:  # skip near-zero contributions
            top_factors.append({
                "feature": available_features[idx],
                "shap_value": round(float(sv[idx]), 4),
                "direction": "increases_risk" if sv[idx] > 0 else "decreases_risk",
                "feature_value": round(float(X_all[i, idx]), 3),
            })

    shap_records.append({
        "CUSTOMER_ID": customer_id,
        "TOP_FACTORS": json.dumps(top_factors),
        "FRAUD_PROBABILITY": fraud_prob,
    })

shap_summary_df = pd.DataFrame(shap_records)

# Write to Snowflake
print("Writing SHAP_SUMMARY to Snowflake...")
session.sql("CREATE OR REPLACE TABLE FEATURES.SHAP_SUMMARY (CUSTOMER_ID VARCHAR, TOP_FACTORS VARIANT, FRAUD_PROBABILITY FLOAT)").collect()

shap_sp = session.create_dataframe(shap_summary_df)
shap_sp = shap_sp.with_column("TOP_FACTORS", F.parse_json(F.col("TOP_FACTORS")))
shap_sp.write.mode("overwrite").save_as_table("FEATURES.SHAP_SUMMARY")
print(f"SHAP_SUMMARY written: {len(shap_records)} rows")

# Log model to registry
print("\nLogging model to registry...")
registry = Registry(session=session, database_name="FRAUD_DETECTION_DEMO", schema_name="MODELS")

sample_input = pd.DataFrame(X_train[:10], columns=available_features)
mv = registry.log_model(
    model=model,
    model_name="FRAUD_DETECTOR",
    version_name="V2",
    sample_input_data=sample_input,
    comment="Regularized + calibrated gradient boosting with label noise for realistic probabilities",
)
print(f"Model logged: FRAUD_DETECTOR V2")

# Print investigation-ready summary
print(f"\n{'='*60}")
print(f"Training complete!")
print(f"  AUC: {auc:.4f}")
print(f"  High-confidence fraud (>0.8): {int((all_probs > 0.8).sum())}")
print(f"  Investigation zone (0.5-0.8): {int(((all_probs > 0.5) & (all_probs <= 0.8)).sum())}")
print(f"  Ambiguous (0.3-0.5): {int(((all_probs > 0.3) & (all_probs <= 0.5)).sum())}")
print(f"  Low risk (<0.3): {int((all_probs <= 0.3).sum())}")
print(f"  Model: FRAUD_DETECTION_DEMO.MODELS.FRAUD_DETECTOR (V2)")
print(f"{'='*60}")

session.close()
