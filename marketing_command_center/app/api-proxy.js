const http = require('http');
const https = require('https');
const fs = require('fs');

const SNOWFLAKE_HOST = process.env.SNOWFLAKE_HOST;
const PORT = 3001;

function getToken() {
  try {
    return fs.readFileSync('/snowflake/session/token', 'utf8').trim();
  } catch {
    return '';
  }
}

const server = http.createServer((req, res) => {
  // Strip /api prefix — nginx sends /api/v2/... and we forward /api/v2/... to Snowflake
  const path = req.url;

  let body = '';
  req.on('data', chunk => { body += chunk; });
  req.on('end', () => {
    const token = getToken();
    const callerToken = req.headers['sf-context-current-user-token'];
    const authToken = callerToken ? `${token}.${callerToken}` : token;

    const options = {
      hostname: SNOWFLAKE_HOST,
      port: 443,
      path: path,
      method: req.method,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Snowflake Token="${authToken}"`,
        'X-Snowflake-Authorization-Token-Type': 'OAUTH',
      },
    };

    const proxyReq = https.request(options, proxyRes => {
      res.writeHead(proxyRes.statusCode, {
        'Content-Type': proxyRes.headers['content-type'] || 'application/json',
        'Transfer-Encoding': proxyRes.headers['transfer-encoding'] || '',
      });
      proxyRes.pipe(res);
    });

    proxyReq.on('error', err => {
      console.error('Proxy error:', err.message);
      res.writeHead(502, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: err.message }));
    });

    if (body) proxyReq.write(body);
    proxyReq.end();
  });
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`API proxy listening on 127.0.0.1:${PORT}, forwarding to ${SNOWFLAKE_HOST}`);
});
