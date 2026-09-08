1... const http = require('http');
2... const https = require('https');
3... const fs = require('fs');
4... 
5... const SNOWFLAKE_HOST = process.env.SNOWFLAKE_HOST;
6... const PORT = 3001;
7... 
8... function getToken() {
9...   try {
10...     return fs.readFileSync('/snowflake/session/token', 'utf8').trim();
11...   } catch {
12...     return '';
13...   }
14... }
15... 
16... const server = http.createServer((req, res) => {
17...   // Strip /api prefix — nginx sends /api/v2/... and we forward /api/v2/... to Snowflake
18...   const path = req.url;
19... 
20...   let body = '';
21...   req.on('data', chunk => { body += chunk; });
22...   req.on('end', () => {
23...     const token = getToken();
24...     const callerToken = req.headers['sf-context-current-user-token'];
25...     const authToken = callerToken ? `${token}.${callerToken}` : token;
26... 
27...     const options = {
28...       hostname: SNOWFLAKE_HOST,
29...       port: 443,
30...       path: path,
31...       method: req.method,
32...       headers: {
33...         'Content-Type': 'application/json',
34...         'Authorization': `Snowflake Token="${authToken}"`,
35...         'X-Snowflake-Authorization-Token-Type': 'OAUTH',
36...       },
37...     };
38... 
39...     const proxyReq = https.request(options, proxyRes => {
40...       res.writeHead(proxyRes.statusCode, {
41...         'Content-Type': proxyRes.headers['content-type'] || 'application/json',
42...         'Transfer-Encoding': proxyRes.headers['transfer-encoding'] || '',
43...       });
44...       proxyRes.pipe(res);
45...     });
46... 
47...     proxyReq.on('error', err => {
48...       console.error('Proxy error:', err.message);
49...       res.writeHead(502, { 'Content-Type': 'application/json' });
50...       res.end(JSON.stringify({ error: err.message }));
51...     });
52... 
53...     if (body) proxyReq.write(body);
54...     proxyReq.end();
55...   });
56... });
57... 
58... server.listen(PORT, '127.0.0.1', () => {
59...   console.log(`API proxy listening on 127.0.0.1:${PORT}, forwarding to ${SNOWFLAKE_HOST}`);
60... });
61... 