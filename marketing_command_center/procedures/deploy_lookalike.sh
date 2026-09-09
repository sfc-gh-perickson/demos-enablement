#!/usr/bin/env bash
set -euo pipefail

# Deploy the Lookalike Builder stored procedure to Snowflake.
# Usage: bash procedures/deploy_lookalike.sh
#
# Requires: snow CLI configured with the parker_demo connection.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECTION="parker_demo"

echo "==> Creating stage..."
snow sql -c "$CONNECTION" -q "CREATE STAGE IF NOT EXISTS SB_COMMAND_CENTER.PROCEDURES.PROC_STAGE"

echo "==> Uploading lookalike_builder.py to stage..."
snow stage copy "$SCRIPT_DIR/lookalike_builder.py" \
  @SB_COMMAND_CENTER.PROCEDURES.PROC_STAGE \
  --overwrite -c "$CONNECTION"

echo "==> Registering stored procedure..."
snow sql -c "$CONNECTION" -q "
CREATE OR REPLACE PROCEDURE SB_COMMAND_CENTER.PROCEDURES.BUILD_LOOKALIKE(
    SEED_CUSTOMER_IDS ARRAY,
    FEATURE_VIEW_NAMES ARRAY,
    MODEL_NAME VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python', 'snowflake-ml-python', 'xgboost', 'scikit-learn', 'pandas', 'numpy')
HANDLER = 'lookalike_builder.build_lookalike'
IMPORTS = ('@SB_COMMAND_CENTER.PROCEDURES.PROC_STAGE/lookalike_builder.py')
EXECUTE AS CALLER;
"

echo "==> Done. Test with:"
echo "    snow sql -c $CONNECTION -q \"CALL SB_COMMAND_CENTER.PROCEDURES.BUILD_LOOKALIKE(ARRAY_CONSTRUCT('CUST-000001','CUST-000002','CUST-000010','CUST-000050'), ARRAY_CONSTRUCT('CUSTOMER_RFM_FV','CUSTOMER_BEHAVIOR_FV'), 'test_lookalike');\""
