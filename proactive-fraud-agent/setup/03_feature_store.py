"""
03_feature_store.py — Feature Store SDK: Entity + Feature View registration
Uses Snowflake ML Feature Store to register CUSTOMER entity and FRAUD_FEATURES view.
"""

from snowflake.snowpark import Session
from snowflake.ml.feature_store import FeatureStore, FeatureView, Entity, CreationMode

# Connect using parker_demo connection
session = Session.builder.config("connection_name", "parker_demo").create()
session.sql("USE DATABASE FRAUD_DETECTION_DEMO").collect()
session.sql("USE SCHEMA FEATURES").collect()
session.sql("USE WAREHOUSE FRAUD_DEMO_WH").collect()

# Initialize Feature Store
fs = FeatureStore(
    session=session,
    database="FRAUD_DETECTION_DEMO",
    name="FEATURES",
    default_warehouse="FRAUD_DEMO_WH",
    creation_mode=CreationMode.CREATE_IF_NOT_EXIST,
)

# Define CUSTOMER entity
customer_entity = Entity(
    name="CUSTOMER",
    join_keys=["CUSTOMER_ID"],
    desc="Customer entity for fraud detection features",
)
fs.register_entity(customer_entity)
print("Registered entity: CUSTOMER")

# Define Feature View sourcing from CUSTOMER_FEATURE_BASE dynamic table
feature_df = session.sql("""
    SELECT
        CUSTOMER_ID,
        VELOCITY_1H,
        VELOCITY_24H,
        VELOCITY_7D,
        VELOCITY_30D,
        VELOCITY_CHANGE_RATIO,
        TOTAL_AMOUNT_24H,
        AVG_AMOUNT_7D,
        MAX_AMOUNT_7D,
        AMOUNT_STDDEV_7D,
        MAX_TO_AVG_RATIO_7D,
        UNIQUE_MERCHANTS_7D,
        NEW_MERCHANT_RATIO_7D,
        PCT_HIGH_RISK_MERCHANT_7D,
        PCT_NEW_MERCHANTS_7D,
        GEO_SPREAD_24H,
        AVG_DISTANCE_FROM_HOME_7D,
        PCT_INTERNATIONAL_7D,
        DISTINCT_CURRENCIES_7D,
        PCT_NIGHT_TXNS_7D,
        PCT_WEEKEND_7D,
        CHANNEL_DIVERSITY_7D,
        DEVICE_SWITCH_COUNT_24H,
        REFUND_TO_PURCHASE_RATIO_7D,
        MAX_AMOUNT_TO_CREDIT_RATIO_7D,
        DORMANCY_DAYS_BEFORE_CURRENT,
        IS_FRAUD_LABEL
    FROM FRAUD_DETECTION_DEMO.CURATED.CUSTOMER_FEATURE_BASE
""")

fraud_features_fv = FeatureView(
    name="FRAUD_FEATURES",
    entities=[customer_entity],
    feature_df=feature_df,
    refresh_freq="5 minutes",
    desc="Fraud detection features: velocity, amounts, geo, behavioral, temporal patterns",
)

fraud_features_fv = fs.register_feature_view(
    feature_view=fraud_features_fv,
    version="V1",
)
print(f"Registered feature view: FRAUD_FEATURES (version V1)")
print(f"Features: {fraud_features_fv.feature_names}")

# Verify
print("\n--- Feature Store Contents ---")
entities_df = fs.list_entities().to_pandas()
print(f"Entities: {entities_df['NAME'].tolist()}")
fv_df = fs.list_feature_views().to_pandas()
print(f"Feature Views: {fv_df['NAME'].tolist()}")

# Sample data
sample = fraud_features_fv.feature_df.limit(5).to_pandas()
print(f"\nSample data ({len(sample)} rows):")
print(sample[["CUSTOMER_ID", "VELOCITY_7D", "AVG_AMOUNT_7D", "IS_FRAUD_LABEL"]].to_string())

session.close()
print("\nFeature Store setup complete.")
