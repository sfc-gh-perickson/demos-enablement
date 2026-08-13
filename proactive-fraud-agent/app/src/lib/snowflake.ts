import snowflake from 'snowflake-sdk';
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';

let connection: any = null;

function loadSnowflakeConfig() {
  // Try reading ~/.snowflake/config.toml for local dev
  try {
    const configPath = join(homedir(), '.snowflake', 'config.toml');
    const raw = readFileSync(configPath, 'utf-8');
    const connName = process.env.SNOWFLAKE_CONNECTION || 'parker_demo';
    const section = raw.split(`[connections.${connName}]`)[1]?.split(/\n\[/)[0] || '';
    const get = (key: string) => {
      const match = section.match(new RegExp(`${key}\\s*=\\s*"?([^"\\n]+)"?`));
      return match ? match[1].trim() : '';
    };
    const account = get('account');
    return { account, user: get('user'), password: get('password') };
  } catch {
    return { account: '', user: '', password: '' };
  }
}

function getSpcsToken(): string | null {
  // In SPCS, an OAuth token is available at /snowflake/session/token
  const tokenPath = '/snowflake/session/token';
  try {
    if (existsSync(tokenPath)) {
      return readFileSync(tokenPath, 'utf-8').trim();
    }
  } catch {}
  return null;
}

function isConnectionValid(): boolean {
  if (!connection) return false;
  try {
    return connection.isUp();
  } catch {
    return false;
  }
}

export async function getConnection() {
  if (isConnectionValid()) return connection;
  connection = null;

  const spcsToken = getSpcsToken();

  if (spcsToken) {
    // Running inside SPCS — use OAuth token auth
    const host = process.env.SNOWFLAKE_HOST || process.env.SNOWFLAKE_ACCOUNT || '';
    connection = snowflake.createConnection({
      accessUrl: `https://${host}`,
      account: process.env.SNOWFLAKE_ACCOUNT || host.split('.')[0],
      authenticator: 'OAUTH',
      token: spcsToken,
      database: process.env.SNOWFLAKE_DATABASE || 'FRAUD_DETECTION_DEMO',
      schema: process.env.SNOWFLAKE_SCHEMA || 'APP',
      warehouse: process.env.SNOWFLAKE_WAREHOUSE || 'FRAUD_DEMO_WH',
      clientSessionKeepAlive: true,
    } as any);
  } else {
    // Local dev — use config.toml credentials
    const config = loadSnowflakeConfig();
    connection = snowflake.createConnection({
      account: process.env.SNOWFLAKE_ACCOUNT || config.account,
      username: process.env.SNOWFLAKE_USER || config.user,
      password: process.env.SNOWFLAKE_PASSWORD || config.password,
      database: process.env.SNOWFLAKE_DATABASE || 'FRAUD_DETECTION_DEMO',
      schema: process.env.SNOWFLAKE_SCHEMA || 'APP',
      warehouse: process.env.SNOWFLAKE_WAREHOUSE || 'FRAUD_DEMO_WH',
    });
  }

  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      connection = null;
      reject(new Error('Snowflake connection timed out after 30s'));
    }, 30000);
    connection.connect((err: any) => {
      clearTimeout(timeout);
      if (err) {
        connection = null;
        reject(err);
      } else {
        resolve(connection);
      }
    });
  });
}

export async function executeQuery(sql: string, binds: any[] = []): Promise<any[]> {
  const run = async () => {
    const conn = await getConnection();
    return new Promise<any[]>((resolve, reject) => {
      conn.execute({
        sqlText: sql,
        binds,
        complete: (err: any, _stmt: any, rows: any[]) => {
          if (err) reject(err);
          else resolve(rows || []);
        },
      });
    });
  };

  try {
    return await run();
  } catch (err: any) {
    if (err.message?.includes('terminated connection')) {
      connection = null;
      return await run();
    }
    throw err;
  }
}

export async function getPriorities() {
  return executeQuery(`
    SELECT p.CUSTOMER_ID, p.FRAUD_PROBABILITY, p.PRIORITY_RANK, p.TOP_FACTORS,
           p.RISK_TIER, p.INVESTIGATION_STATUS, p.SCORED_AT,
           r.RECOMMENDED_ACTION, r.INVESTIGATED_AT,
           c.CREDIT_LIMIT,
           COALESCE(t.RECENT_TXN_VOLUME, 0) AS RECENT_TXN_VOLUME,
           p.FRAUD_PROBABILITY * COALESCE(c.CREDIT_LIMIT, 0) AS EXPECTED_LOSS
    FROM APP.PRIORITIES p
    LEFT JOIN APP.INVESTIGATION_REPORTS r ON p.CUSTOMER_ID = r.CUSTOMER_ID
    LEFT JOIN RAW.CUSTOMERS c ON p.CUSTOMER_ID = c.CUSTOMER_ID
    LEFT JOIN (
      SELECT CUSTOMER_ID, SUM(TRANSACTION_AMOUNT) AS RECENT_TXN_VOLUME
      FROM RAW.TRANSACTIONS
      WHERE TRANSACTION_TIMESTAMP >= DATEADD('day', -30, CURRENT_TIMESTAMP())
      GROUP BY CUSTOMER_ID
    ) t ON p.CUSTOMER_ID = t.CUSTOMER_ID
    ORDER BY p.PRIORITY_RANK
  `);
}

export async function getInvestigation(customerId: string) {
  return executeQuery(`
    SELECT p.CUSTOMER_ID, p.PRIORITY_RANK, p.FRAUD_PROBABILITY, p.TOP_FACTORS,
           p.RISK_TIER, p.INVESTIGATION_STATUS,
           r.INVESTIGATION_REPORT, r.RECOMMENDED_ACTION, r.THREAD_ID, r.PARENT_MESSAGE_ID,
           r.INVESTIGATED_AT,
           c.FIRST_NAME, c.LAST_NAME, c.EMAIL, c.PHONE,
           c.ADDRESS_CITY, c.ADDRESS_STATE, c.ACCOUNT_OPEN_DATE,
           c.ACCOUNT_STATUS, c.CREDIT_LIMIT
    FROM APP.PRIORITIES p
    LEFT JOIN APP.INVESTIGATION_REPORTS r ON p.CUSTOMER_ID = r.CUSTOMER_ID
    LEFT JOIN RAW.CUSTOMERS c ON p.CUSTOMER_ID = c.CUSTOMER_ID
    WHERE p.CUSTOMER_ID = ?
    ORDER BY r.INVESTIGATED_AT DESC
    LIMIT 1
  `, [customerId]);
}

export async function continueThread(threadId: string, parentMessageId: string, message: string) {
  // thread_id and parent_message_id must be integers for DATA_AGENT_RUN
  // parentMessageId may be in format "threadId-messageId" or just a number
  let msgId = parentMessageId;
  if (parentMessageId.includes('-')) {
    // Format: "58553664309-3837372890581618" — use the second part
    msgId = parentMessageId.split('-').pop() || parentMessageId;
  }

  const requestBody = JSON.stringify({
    messages: [{ role: 'user', content: [{ type: 'text', text: message }] }],
    thread_id: parseInt(threadId, 10),
    parent_message_id: parseInt(msgId, 10),
  });

  const result = await executeQuery(`
    SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
      'FRAUD_DETECTION_DEMO.APP.FRAUD_INVESTIGATOR',
      ?,
      FALSE
    ) AS response
  `, [requestBody]);

  const raw = result[0]?.RESPONSE || result[0]?.response;
  if (!raw) return { text: 'No response', parentMessageId };

  // Parse the response
  let parsed: any;
  try {
    parsed = typeof raw === 'string' ? JSON.parse(raw) : raw;
  } catch {
    return { text: typeof raw === 'string' ? raw : JSON.stringify(raw), parentMessageId };
  }

  // Extract text from content array
  let text = '';
  if (parsed.content && Array.isArray(parsed.content)) {
    const textParts = parsed.content
      .filter((c: any) => c.type === 'text')
      .map((c: any) => c.text);
    if (textParts.length > 0) text = textParts.join('\n');
  }
  if (!text) {
    text = parsed.message || (typeof parsed === 'string' ? parsed : JSON.stringify(parsed, null, 2));
  }

  // Extract new parent_message_id (assistant_message_id) for next turn
  const newParentMessageId = parsed.metadata?.assistant_message_id?.toString() || parentMessageId;

  return { text, parentMessageId: newParentMessageId };
}

export async function startNewThread(message: string) {
  const requestBody = JSON.stringify({
    messages: [{ role: 'user', content: [{ type: 'text', text: message }] }],
  });

  const result = await executeQuery(`
    SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
      'FRAUD_DETECTION_DEMO.APP.FRAUD_INVESTIGATOR',
      ?,
      TRUE
    ) AS response
  `, [requestBody]);

  const raw = result[0]?.RESPONSE || result[0]?.response;
  if (!raw) return { text: 'No response', threadId: '', parentMessageId: '' };

  let parsed: any;
  try {
    parsed = typeof raw === 'string' ? JSON.parse(raw) : raw;
  } catch {
    return { text: typeof raw === 'string' ? raw : JSON.stringify(raw), threadId: '', parentMessageId: '' };
  }

  let text = '';
  if (parsed.content && Array.isArray(parsed.content)) {
    const textParts = parsed.content.filter((c: any) => c.type === 'text').map((c: any) => c.text);
    if (textParts.length > 0) text = textParts.join('\n');
  }
  if (!text) {
    text = parsed.message || (typeof parsed === 'string' ? parsed : JSON.stringify(parsed, null, 2));
  }

  const metadata = parsed.metadata || {};
  const threadId = metadata.thread_id?.toString() || '';
  const parentMessageId = metadata.assistant_message_id?.toString() || metadata.message_id?.toString() || '';

  return { text, threadId, parentMessageId };
}

export async function updateStatus(customerId: string, status: string) {
  await executeQuery(`
    UPDATE APP.PRIORITIES
    SET INVESTIGATION_STATUS = ?
    WHERE CUSTOMER_ID = ?
  `, [status, customerId]);
}

export async function getTransactionHistory(customerId: string) {
  return executeQuery(`
    SELECT TRANSACTION_ID, TRANSACTION_AMOUNT, TRANSACTION_TIMESTAMP,
           CHANNEL, TRANSACTION_TYPE, MERCHANT_ID, IS_INTERNATIONAL, DEVICE_TYPE
    FROM RAW.TRANSACTIONS
    WHERE CUSTOMER_ID = ?
    ORDER BY TRANSACTION_TIMESTAMP DESC
    LIMIT 20
  `, [customerId]);
}
