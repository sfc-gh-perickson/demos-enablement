#!/usr/bin/env bash
set -euo pipefail

# Deploy the Marketing Command Center app to SPCS.
# Usage: bash app/deploy_app.sh
#
# Requires: snow CLI (my_connection connection), Docker running.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECTION="my_connection"
DATABASE="SB_COMMAND_CENTER"
SCHEMA="PUBLIC"
REPO="IMAGE_REPO"
IMAGE_NAME="marketing-command-center"
IMAGE_TAG="latest"
COMPUTE_POOL="SB_APP_POOL"
SERVICE_NAME="MARKETING_COMMAND_CENTER"

# --- 1. Build the frontend ---
echo "==> Installing dependencies..."
(cd "$SCRIPT_DIR" && npm ci --silent)

echo "==> Building app..."
(cd "$SCRIPT_DIR" && npm run build --silent)

# --- 2. Create image repository ---
echo "==> Creating image repository (if needed)..."
snow sql -c "$CONNECTION" -q \
  "CREATE IMAGE REPOSITORY IF NOT EXISTS ${DATABASE}.${SCHEMA}.${REPO}"

# --- 3. Get registry URL and build full image path ---
REGISTRY_URL=$(snow spcs image-registry url -c "$CONNECTION" 2>/dev/null | tr -d '[:space:]')
FULL_IMAGE="${REGISTRY_URL}/${DATABASE}/${SCHEMA}/${REPO}/${IMAGE_NAME}:${IMAGE_TAG}"
FULL_IMAGE=$(echo "$FULL_IMAGE" | tr '[:upper:]' '[:lower:]')

echo "==> Image: ${FULL_IMAGE}"

# --- 4. Docker login, build, push ---
echo "==> Logging into Snowflake image registry..."
snow spcs image-registry login -c "$CONNECTION"

echo "==> Building Docker image..."
docker build --platform linux/amd64 -t "$FULL_IMAGE" "$SCRIPT_DIR"

echo "==> Pushing image to Snowflake..."
docker push "$FULL_IMAGE"

# --- 5. Create or replace the service ---
IMAGE_PATH=$(echo "/${DATABASE}/${SCHEMA}/${REPO}/${IMAGE_NAME}:${IMAGE_TAG}" | tr '[:upper:]' '[:lower:]')

echo "==> Dropping existing service (if any)..."
snow sql -c "$CONNECTION" -q \
  "DROP SERVICE IF EXISTS ${DATABASE}.${SCHEMA}.${SERVICE_NAME}"

echo "==> Creating SPCS service..."
snow sql -c "$CONNECTION" -q "
CREATE SERVICE ${DATABASE}.${SCHEMA}.${SERVICE_NAME}
  IN COMPUTE POOL ${COMPUTE_POOL}
  FROM SPECIFICATION
  \$\$
  spec:
    containers:
      - name: app
        image: ${IMAGE_PATH}
        resources:
          requests:
            cpu: \"1\"
            memory: \"2Gi\"
          limits:
            cpu: \"2\"
            memory: \"4Gi\"
        env:
          SNOWFLAKE_DATABASE: ${DATABASE}
    endpoints:
      - name: app
        port: 80
        public: true
  \$\$;
"

echo "==> Waiting for service to start..."
for i in $(seq 1 24); do
  sleep 5
  STATUS=$(snow sql -c "$CONNECTION" -q \
    "SELECT PARSE_JSON(SYSTEM\$GET_SERVICE_STATUS('${DATABASE}.${SCHEMA}.${SERVICE_NAME}'))[0]['status']::STRING AS status" \
    --format csv 2>/dev/null | tail -1 | tr -d '"')
  if [ "$STATUS" = "READY" ]; then
    break
  fi
  echo "    Status: ${STATUS:-PENDING} (${i}/24)..."
done

APP_URL=$(snow sql -c "$CONNECTION" -q \
  "SHOW ENDPOINTS IN SERVICE ${DATABASE}.${SCHEMA}.${SERVICE_NAME}" \
  --format csv 2>/dev/null | tail -1 | awk -F',' '{print $NF}' | tr -d '"')

echo ""
if [ "$STATUS" = "READY" ] && [ -n "$APP_URL" ] && [ "$APP_URL" != "Endpoints provisioning in progress... check back in a few minutes" ]; then
  echo "==> App is live at: https://${APP_URL}"
else
  echo "==> Service is starting. Check back shortly:"
  echo "    snow sql -c ${CONNECTION} -q \"SHOW ENDPOINTS IN SERVICE ${DATABASE}.${SCHEMA}.${SERVICE_NAME}\""
  echo "    snow sql -c ${CONNECTION} -q \"SELECT SYSTEM\\\$GET_SERVICE_STATUS('${DATABASE}.${SCHEMA}.${SERVICE_NAME}')\""
fi
