import snowflake.connector
from snowflake.snowpark import Session
from snowflake.ml.feature_store import FeatureStore, CreationMode, OnlineConfig

conn = snowflake.connector.connect(connection_name='parker_demo')
s = Session.builder.configs({'connection': conn}).create()
for q in ['USE ROLE ACCOUNTADMIN', 'USE DATABASE GRAPH_FRAUD_DEMO', 'USE SCHEMA FEATURES', 'USE WAREHOUSE GRAPH_FRAUD_WH']:
    s.sql(q).collect()
fs = FeatureStore(session=s, database='GRAPH_FRAUD_DEMO', name='FEATURES',
                  default_warehouse='GRAPH_FRAUD_WH', creation_mode=CreationMode.FAIL_IF_NOT_EXIST)

# Combined (realtime) FV first since it depends on the others
for n in ['COMBINED_FRAUD_FEATURES', 'ADDRESS_COMMUNITY_FEATURES', 'GRAPH_COMMUNITY_FEATURES',
          'IP_COMMUNITY_FEATURES', 'STREAM_VELOCITY']:
    try:
        fs.update_feature_view(name=n, version='V1', online_config=OnlineConfig(enable=False))
        print(n, 'online now =', fs.get_feature_view(n, 'V1').online)
    except Exception as e:
        print(n, 'ERR', type(e).__name__, str(e)[:400])
