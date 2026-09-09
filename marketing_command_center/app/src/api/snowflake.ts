export async function executeSQL(sql: string): Promise<Record<string, unknown>[]> {
  const response = await fetch('/api/v2/statements', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      statement: sql,
      timeout: 300,
      database: 'SB_COMMAND_CENTER',
      warehouse: 'COMPUTE_WH',
    }),
  });

  const data = await response.json();

  // If data is already in the response, parse it directly
  if (data.data) {
    return parseResultSet(data);
  }

  // Otherwise poll the status URL for async queries
  if (data.statementStatusUrl) {
    return await pollForResults(data.statementStatusUrl);
  }

  return [];
}

async function pollForResults(url: string): Promise<Record<string, unknown>[]> {
  for (let i = 0; i < 120; i++) {
    await new Promise(r => setTimeout(r, 2000));
    const res = await fetch(url);
    const data = await res.json();
    if (data.data) return parseResultSet(data);
    if (data.code && data.code !== '333334') throw new Error(data.message);
  }
  throw new Error('Query timeout');
}

function parseResultSet(data: { resultSetMetaData?: { rowType?: { name: string }[] }; data?: string[][] }): Record<string, unknown>[] {
  const columns = data.resultSetMetaData?.rowType?.map(c => c.name) || [];
  const rows = data.data || [];
  return rows.map(row => {
    const obj: Record<string, unknown> = {};
    columns.forEach((col, i) => { obj[col] = row[i]; });
    return obj;
  });
}
