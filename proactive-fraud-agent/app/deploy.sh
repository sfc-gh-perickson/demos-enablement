#!/bin/bash
# Deploy the Fraud Investigation Portal to SPCS
# Prerequisites: snow CLI configured, Docker running

set -e

REPO="FRAUD_DETECTION_DEMO.APP.FRAUD_APP_REPO"
IMAGE_NAME="fraud-portal"
TAG="latest"

echo "=== Step 1: Create compute pool and image repository ==="
snow sql -q "CREATE COMPUTE POOL IF NOT EXISTS FRAUD_APP_POOL
  MIN_NODES = 1 MAX_NODES = 1
  INSTANCE_FAMILY = CPU_X64_XS
  AUTO_RESUME = TRUE
  AUTO_SUSPEND_SECS = 300;" -c parker_demo

snow sql -q "CREATE IMAGE REPOSITORY IF NOT EXISTS ${REPO};" -c parker_demo

echo "=== Step 2: Get registry URL and login ==="
REGISTRY_URL=$(snow sql -q "SHOW IMAGE REPOSITORIES LIKE 'FRAUD_APP_REPO' IN SCHEMA FRAUD_DETECTION_DEMO.APP;" -c parker_demo --format json | python3 -c "import sys,json; data=json.load(sys.stdin); print(data[0]['repository_url'])")

echo "Registry URL: ${REGISTRY_URL}"
REGISTRY_HOST=$(echo "${REGISTRY_URL}" | cut -d'/' -f1)

# Authenticate with Snowflake registry using your credentials
# Option 1: Use snow spcs image-registry login (preferred)
# Option 2: Manual docker login with Snowflake username + PAT/password
echo ""
echo "Logging into registry ${REGISTRY_HOST}..."
snow spcs image-registry login -c parker_demo 2>/dev/null || \
  docker login "${REGISTRY_HOST}" -u PERICKSON

echo "=== Step 3: Build and push Docker image ==="
cd "$(dirname "$0")"
docker build --platform linux/amd64 -t "${REGISTRY_URL}/${IMAGE_NAME}:${TAG}" .
docker push "${REGISTRY_URL}/${IMAGE_NAME}:${TAG}"

echo "=== Step 4: Create/update the service ==="
snow sql -q "DROP SERVICE IF EXISTS FRAUD_DETECTION_DEMO.APP.FRAUD_INVESTIGATION_PORTAL;" -c parker_demo
snow sql -q "
CREATE SERVICE FRAUD_DETECTION_DEMO.APP.FRAUD_INVESTIGATION_PORTAL
  IN COMPUTE POOL FRAUD_APP_POOL
  QUERY_WAREHOUSE = FRAUD_DEMO_WH
  MIN_INSTANCES = 1
  MAX_INSTANCES = 1
  FROM SPECIFICATION \$\$
  spec:
    containers:
      - name: app
        image: /FRAUD_DETECTION_DEMO/APP/FRAUD_APP_REPO/${IMAGE_NAME}:${TAG}
        env:
          SNOWFLAKE_ACCOUNT: SFSENORTHAMERICA-PERICKSON_AWS1
          SNOWFLAKE_HOST: sfsenorthamerica-perickson_aws1.snowflakecomputing.com
          SNOWFLAKE_DATABASE: FRAUD_DETECTION_DEMO
          SNOWFLAKE_SCHEMA: APP
          SNOWFLAKE_WAREHOUSE: FRAUD_DEMO_WH
    endpoints:
      - name: app
        port: 3000
        public: true
  \$\$;
" -c parker_demo

echo "=== Step 5: Check service status ==="
snow sql -q "SHOW SERVICES LIKE 'FRAUD_INVESTIGATION_PORTAL' IN SCHEMA FRAUD_DETECTION_DEMO.APP;" -c parker_demo

echo ""
echo "=== Deployment complete ==="
echo "Run: snow sql -q \"SHOW ENDPOINTS IN SERVICE FRAUD_DETECTION_DEMO.APP.FRAUD_INVESTIGATION_PORTAL;\" -c parker_demo"
echo "to get the public URL."
