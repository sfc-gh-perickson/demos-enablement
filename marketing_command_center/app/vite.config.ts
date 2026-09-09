import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { readFileSync } from 'fs';
import { resolve } from 'path';
import { parse } from 'smol-toml';

function loadSnowflakeConfig() {
  const configPath = resolve(process.env.HOME || '~', '.snowflake/config.toml');
  const raw = readFileSync(configPath, 'utf8');
  const config = parse(raw) as Record<string, any>;
  const conn = config.connections?.parker_demo;
  if (!conn) throw new Error('Connection parker_demo not found in ~/.snowflake/config.toml');
  return { account: conn.account as string, pat: conn.password as string };
}

const sf = loadSnowflakeConfig();

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': {
        target: `https://${sf.account}.snowflakecomputing.com`,
        changeOrigin: true,
        secure: true,
        headers: {
          'Authorization': `Bearer ${sf.pat}`,
          'X-Snowflake-Authorization-Token-Type': 'PROGRAMMATIC_ACCESS_TOKEN',
          'Accept': 'application/json',
          'User-Agent': 'SBCommandCenter/1.0',
        },
      },
    },
  },
});
