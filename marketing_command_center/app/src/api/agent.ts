1... export interface AgentMessage {
2...   role: 'user' | 'assistant';
3...   content: string;
4... }
5... 
6... export type ContentBlock =
7...   | { type: 'text'; text: string }
8...   | { type: 'table'; title: string; columns: string[]; rows: string[][] }
9...   | { type: 'chart'; spec: string }
10...   | { type: 'thinking'; text: string };
11... 
12... export interface StreamResult {
13...   blocks: ContentBlock[];
14... }
15... 
16... export async function streamAgentResponse(
17...   messages: AgentMessage[],
18...   onStatus: (status: string) => void
19... ): Promise<StreamResult> {
20...   const response = await fetch('/api/v2/databases/SB_COMMAND_CENTER/schemas/AGENTS/agents/MARKETING_COMMAND_CENTER:run', {
21...     method: 'POST',
22...     headers: { 'Content-Type': 'application/json' },
23...     body: JSON.stringify({
24...       messages: messages.map(m => ({ role: m.role, content: [{ type: 'text', text: m.content }] })),
25...       stream: true,
26...     }),
27...   });
28... 
29...   if (!response.ok) {
30...     const err = await response.text();
31...     throw new Error(`Agent error ${response.status}: ${err.substring(0, 200)}`);
32...   }
33... 
34...   const reader = response.body?.getReader();
35...   if (!reader) return { blocks: [] };
36... 
37...   const decoder = new TextDecoder();
38...   let buffer = '';
39... 
40...   // Track content by content_index: { type, data }
41...   const contentMap = new Map<number, { kind: 'text' | 'table' | 'chart'; data: unknown }>();
42... 
43...   while (true) {
44...     const { done, value } = await reader.read();
45...     if (done) break;
46... 
47...     buffer += decoder.decode(value, { stream: true });
48...     const lines = buffer.split('\n');
49...     buffer = lines.pop() || '';
50... 
51...     let currentEvent = '';
52...     for (const line of lines) {
53...       if (line.startsWith('event: ')) {
54...         currentEvent = line.slice(7).trim();
55...       } else if (line.startsWith('data: ')) {
56...         const data = line.slice(6);
57...         if (data === '[DONE]') break;
58...         try {
59...           const parsed = JSON.parse(data);
60...           const idx = parsed.content_index;
61... 
62...           if (currentEvent === 'response.text.delta') {
63...             const existing = contentMap.get(idx);
64...             if (existing && existing.kind === 'text') {
65...               existing.data = (existing.data as string) + (parsed.text || '');
66...             } else {
67...               contentMap.set(idx, { kind: 'text', data: parsed.text || '' });
68...             }
69...           } else if (currentEvent === 'response.table') {
70...             const rs = parsed.result_set;
71...             if (rs) {
72...               contentMap.set(idx, {
73...                 kind: 'table',
74...                 data: {
75...                   title: parsed.title || '',
76...                   columns: rs.resultSetMetaData?.rowType?.map((c: { name: string }) => c.name) || [],
77...                   rows: rs.data || [],
78...                 },
79...               });
80...             }
81...           } else if (currentEvent === 'response.chart') {
82...             if (parsed.chart_spec) {
83...               contentMap.set(idx, { kind: 'chart', data: parsed.chart_spec });
84...             }
85...           } else if (currentEvent === 'response.status' && parsed.message) {
86...             onStatus(parsed.message);
87...           }
88...         } catch {}
89...         currentEvent = '';
90...       }
91...     }
92...   }
93... 
94...   // Build ordered content blocks
95...   // Short text blocks that appear before any non-text content are planning/thinking.
96...   // Everything after the first non-text block (or long text) is the answer.
97...   const entries = [...contentMap.entries()].sort((a, b) => a[0] - b[0]);
98...   const blocks: ContentBlock[] = [];
99...   let seenSubstantive = false;
100... 
101...   for (const [, { kind, data }] of entries) {
102...     if (kind === 'text') {
103...       const text = data as string;
104...       if (!seenSubstantive && text.length < 150) {
105...         blocks.push({ type: 'thinking', text });
106...       } else {
107...         seenSubstantive = true;
108...         blocks.push({ type: 'text', text });
109...       }
110...     } else if (kind === 'table') {
111...       seenSubstantive = true;
112...       const t = data as { title: string; columns: string[]; rows: string[][] };
113...       blocks.push({ type: 'table', title: t.title, columns: t.columns, rows: t.rows });
114...     } else if (kind === 'chart') {
115...       seenSubstantive = true;
116...       blocks.push({ type: 'chart', spec: data as string });
117...     }
118...   }
119... 
120...   return { blocks };
121... }
122... 