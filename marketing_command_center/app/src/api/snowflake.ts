1... export async function executeSQL(sql: string): Promise<Record<string, unknown>[]> {
2...   const response = await fetch('/api/v2/statements', {
3...     method: 'POST',
4...     headers: { 'Content-Type': 'application/json' },
5...     body: JSON.stringify({
6...       statement: sql,
7...       timeout: 300,
8...       database: 'SB_COMMAND_CENTER',
9...       warehouse: 'COMPUTE_WH',
10...     }),
11...   });
12... 
13...   const data = await response.json();
14... 
15...   // If data is already in the response, parse it directly
16...   if (data.data) {
17...     return parseResultSet(data);
18...   }
19... 
20...   // Otherwise poll the status URL for async queries
21...   if (data.statementStatusUrl) {
22...     return await pollForResults(data.statementStatusUrl);
23...   }
24... 
25...   return [];
26... }
27... 
28... async function pollForResults(url: string): Promise<Record<string, unknown>[]> {
29...   for (let i = 0; i < 120; i++) {
30...     await new Promise(r => setTimeout(r, 2000));
31...     const res = await fetch(url);
32...     const data = await res.json();
33...     if (data.data) return parseResultSet(data);
34...     if (data.code && data.code !== '333334') throw new Error(data.message);
35...   }
36...   throw new Error('Query timeout');
37... }
38... 
39... function parseResultSet(data: { resultSetMetaData?: { rowType?: { name: string }[] }; data?: string[][] }): Record<string, unknown>[] {
40...   const columns = data.resultSetMetaData?.rowType?.map(c => c.name) || [];
41...   const rows = data.data || [];
42...   return rows.map(row => {
43...     const obj: Record<string, unknown> = {};
44...     columns.forEach((col, i) => { obj[col] = row[i]; });
45...     return obj;
46...   });
47... }
48... 