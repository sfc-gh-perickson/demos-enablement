1... #!/usr/bin/env bash
2... set -euo pipefail
3... 
4... # Deploy the Marketing Command Center app to SPCS.
5... # Usage: bash app/deploy_app.sh
6... #
7... # Requires: snow CLI (my_connection connection), Docker running.
8... 
9... SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
10... CONNECTION="my_connection"
11... DATABASE="SB_COMMAND_CENTER"
12... SCHEMA="PUBLIC"
13... REPO="IMAGE_REPO"
14... IMAGE_NAME="marketing-command-center"
15... IMAGE_TAG="latest"
16... COMPUTE_POOL="SB_APP_POOL"
17... SERVICE_NAME="MARKETING_COMMAND_CENTER"
18... 
19... # --- 1. Build the frontend ---
20... echo "==> Installing dependencies..."
21... (cd "$SCRIPT_DIR" && npm ci --silent)
22... 
23... echo "==> Building app..."
24... (cd "$SCRIPT_DIR" && npm run build --silent)
25... 
26... # --- 2. Create image repository ---
27... echo "==> Creating image repository (if needed)..."
28... snow sql -c "$CONNECTION" -q \
29...   "CREATE IMAGE REPOSITORY IF NOT EXISTS ${DATABASE}.${SCHEMA}.${REPO}"
30... 
31... # --- 3. Get registry URL and build full image path ---
32... REGISTRY_URL=$(snow spcs image-registry url -c "$CONNECTION" 2>/dev/null | tr -d '[:space:]')
33... FULL_IMAGE="${REGISTRY_URL}/${DATABASE}/${SCHEMA}/${REPO}/${IMAGE_NAME}:${IMAGE_TAG}"
34... FULL_IMAGE=$(echo "$FULL_IMAGE" | tr '[:upper:]' '[:lower:]')
35... 
36... echo "==> Image: ${FULL_IMAGE}"
37... 
38... # --- 4. Docker login, build, push ---
39... echo "==> Logging into Snowflake image registry..."
40... snow spcs image-registry login -c "$CONNECTION"
41... 
42... echo "==> Building Docker image..."
43... docker build --platform linux/amd64 -t "$FULL_IMAGE" "$SCRIPT_DIR"
44... 
45... echo "==> Pushing image to Snowflake..."
46... docker push "$FULL_IMAGE"
47... 
48... # --- 5. Create or replace the service ---
49... IMAGE_PATH=$(echo "/${DATABASE}/${SCHEMA}/${REPO}/${IMAGE_NAME}:${IMAGE_TAG}" | tr '[:upper:]' '[:lower:]')
50... 
51... echo "==> Dropping existing service (if any)..."
52... snow sql -c "$CONNECTION" -q \
53...   "DROP SERVICE IF EXISTS ${DATABASE}.${SCHEMA}.${SERVICE_NAME}"
54... 
55... echo "==> Creating SPCS service..."
56... snow sql -c "$CONNECTION" -q "
57... CREATE SERVICE ${DATABASE}.${SCHEMA}.${SERVICE_NAME}
58...   IN COMPUTE POOL ${COMPUTE_POOL}
59...   FROM SPECIFICATION
60...   \$\$
61...   spec:
62...     containers:
63...       - name: app
64...         image: ${IMAGE_PATH}
65...         resources:
66...           requests:
67...             cpu: \"1\"
68...             memory: \"2Gi\"
69...           limits:
70...             cpu: \"2\"
71...             memory: \"4Gi\"
72...         env:
73...           SNOWFLAKE_DATABASE: ${DATABASE}
74...     endpoints:
75...       - name: app
76...         port: 80
77...         public: true
78...   \$\$;
79... "
80... 
81... echo "==> Waiting for service to start..."
82... for i in $(seq 1 24); do
83...   sleep 5
84...   STATUS=$(snow sql -c "$CONNECTION" -q \
85...     "SELECT PARSE_JSON(SYSTEM\$GET_SERVICE_STATUS('${DATABASE}.${SCHEMA}.${SERVICE_NAME}'))[0]['status']::STRING AS status" \
86...     --format csv 2>/dev/null | tail -1 | tr -d '"')
87...   if [ "$STATUS" = "READY" ]; then
88...     break
89...   fi
90...   echo "    Status: ${STATUS:-PENDING} (${i}/24)..."
91... done
92... 
93... APP_URL=$(snow sql -c "$CONNECTION" -q \
94...   "SHOW ENDPOINTS IN SERVICE ${DATABASE}.${SCHEMA}.${SERVICE_NAME}" \
95...   --format csv 2>/dev/null | tail -1 | awk -F',' '{print $NF}' | tr -d '"')
96... 
97... echo ""
98... if [ "$STATUS" = "READY" ] && [ -n "$APP_URL" ] && [ "$APP_URL" != "Endpoints provisioning in progress... check back in a few minutes" ]; then
99...   echo "==> App is live at: https://${APP_URL}"
100... else
101...   echo "==> Service is starting. Check back shortly:"
102...   echo "    snow sql -c ${CONNECTION} -q \"SHOW ENDPOINTS IN SERVICE ${DATABASE}.${SCHEMA}.${SERVICE_NAME}\""
103...   echo "    snow sql -c ${CONNECTION} -q \"SELECT SYSTEM\\\$GET_SERVICE_STATUS('${DATABASE}.${SCHEMA}.${SERVICE_NAME}')\""
104... fi
105... 