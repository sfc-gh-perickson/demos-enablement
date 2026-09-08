1... import { defineConfig } from 'vite';
2... import react from '@vitejs/plugin-react';
3... import { readFileSync } from 'fs';
4... import { resolve } from 'path';
5... import { parse } from 'smol-toml';
6... 
7... function loadSnowflakeConfig() {
8...   const configPath = resolve(process.env.HOME || '~', '.snowflake/config.toml');
9...   const raw = readFileSync(configPath, 'utf8');
10...   const config = parse(raw) as Record<string, any>;
11...   const conn = config.connections?.my_connection;
12...   if (!conn) throw new Error('Connection my_connection not found in ~/.snowflake/config.toml');
13...   return { account: conn.account as string, pat: conn.password as string };
14... }
15... 
16... const sf = loadSnowflakeConfig();
17... 
18... export default defineConfig({
19...   plugins: [react()],
20...   server: {
21...     proxy: {
22...       '/api': {
23...         target: `https://${sf.account}.snowflakecomputing.com`,
24...         changeOrigin: true,
25...         secure: true,
26...         headers: {
27...           'Authorization': `Bearer ${sf.pat}`,
28...           'X-Snowflake-Authorization-Token-Type': 'PROGRAMMATIC_ACCESS_TOKEN',
29...           'Accept': 'application/json',
30...           'User-Agent': 'SBCommandCenter/1.0',
31...         },
32...       },
33...     },
34...   },
35... });
36... 