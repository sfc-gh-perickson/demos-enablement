#!/bin/sh
set -e

# Start the API proxy (Node.js reads /snowflake/session/token for auth)
node /app/api-proxy.js &

# Start nginx in the foreground
exec nginx -g 'daemon off;'
