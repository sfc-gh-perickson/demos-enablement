1... import { useState, useRef, useEffect } from 'react';
2... import Markdown from 'react-markdown';
3... import { streamAgentResponse, AgentMessage, ContentBlock } from '../api/agent';
4... 
5... interface DisplayMessage {
6...   role: 'user' | 'assistant';
7...   content: string;
8...   blocks?: ContentBlock[];
9... }
10... 
11... interface AgentChatProps {
12...   initialMessage?: string;
13...   onFirstMessage?: (text: string) => void;
14... }
15... 
16... export default function AgentChat({ initialMessage, onFirstMessage }: AgentChatProps) {
17...   const [messages, setMessages] = useState<DisplayMessage[]>([]);
18...   const [input, setInput] = useState('');
19...   const [streaming, setStreaming] = useState(false);
20...   const [statusText, setStatusText] = useState('');
21...   const bottomRef = useRef<HTMLDivElement>(null);
22...   const initialSent = useRef(false);
23... 
24...   useEffect(() => {
25...     bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
26...   }, [messages, statusText]);
27... 
28...   useEffect(() => {
29...     if (initialMessage && !initialSent.current) {
30...       initialSent.current = true;
31...       sendMessage(initialMessage);
32...     }
33...   }, [initialMessage]);
34... 
35...   async function sendMessage(text: string) {
36...     if (!text.trim() || streaming) return;
37... 
38...     const userMsg: DisplayMessage = { role: 'user', content: text.trim() };
39...     const newMessages = [...messages, userMsg];
40...     setMessages(newMessages);
41...     setInput('');
42...     setStreaming(true);
43...     setStatusText('Planning...');
44...     if (onFirstMessage && newMessages.length === 1) onFirstMessage(text.trim());
45... 
46...     try {
47...       const agentMessages: AgentMessage[] = newMessages.map(m => ({ role: m.role, content: m.content }));
48...       const result = await streamAgentResponse(agentMessages, setStatusText);
49...       const textContent = result.blocks.filter(b => b.type === 'text').map(b => (b as { type: 'text'; text: string }).text).join('\n\n');
50... 
51...       setMessages([...newMessages, {
52...         role: 'assistant',
53...         content: textContent,
54...         blocks: result.blocks,
55...       }]);
56...     } catch (err) {
57...       setMessages([...newMessages, {
58...         role: 'assistant',
59...         content: `Error: ${err instanceof Error ? err.message : 'Unknown'}`,
60...       }]);
61...     } finally {
62...       setStreaming(false);
63...       setStatusText('');
64...     }
65...   }
66... 
67...   return (
68...     <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
69...       <div style={{ padding: '12px 16px', borderBottom: '1px solid #e5e7eb', fontWeight: 500, fontSize: 14 }}>
70...         Marketing Command Center Agent
71...       </div>
72... 
73...       <div style={{ flex: 1, overflow: 'auto', padding: 16 }}>
74...         {messages.length === 0 && (
75...           <p style={{ color: '#999', fontSize: 13, textAlign: 'center', marginTop: 40 }}>
76...             Ask about forecasts, customer segments, or sales trends.
77...           </p>
78...         )}
79...         {messages.map((msg, i) => (
80...           <div key={i} style={{ marginBottom: 12, textAlign: msg.role === 'user' ? 'right' : 'left' }}>
81...             {msg.role === 'user' ? (
82...               <div style={{
83...                 display: 'inline-block', maxWidth: '85%', padding: '8px 12px', borderRadius: 12,
84...                 background: '#2563eb', color: '#fff', fontSize: 13, lineHeight: 1.5,
85...               }}>
86...                 {msg.content}
87...               </div>
88...             ) : (
89...               <div style={{ maxWidth: '95%', textAlign: 'left' }}>
90...                 {msg.blocks ? (
91...                   <BlockRenderer blocks={msg.blocks} />
92...                 ) : (
93...                   <div style={{ ...bubbleStyle }}>
94...                     <div className="agent-markdown"><Markdown>{msg.content}</Markdown></div>
95...                   </div>
96...                 )}
97...               </div>
98...             )}
99...           </div>
100...         ))}
101...         {streaming && (
102...           <div style={{ marginBottom: 12 }}>
103...             <div style={{ ...bubbleStyle, color: '#6b7280' }}>
104...               {statusText || 'Thinking...'}
105...               <span style={{ marginLeft: 4 }}>...</span>
106...             </div>
107...           </div>
108...         )}
109...         <div ref={bottomRef} />
110...       </div>
111... 
112...       <div style={{ padding: 12, borderTop: '1px solid #e5e7eb', display: 'flex', gap: 8 }}>
113...         <input
114...           value={input}
115...           onChange={e => setInput(e.target.value)}
116...           onKeyDown={e => e.key === 'Enter' && sendMessage(input)}
117...           placeholder="Ask a question..."
118...           style={{ flex: 1, padding: '8px 12px', border: '1px solid #ddd', borderRadius: 8, fontSize: 13 }}
119...         />
120...         <button
121...           onClick={() => sendMessage(input)}
122...           disabled={streaming || !input.trim()}
123...           style={{
124...             padding: '8px 16px', background: '#2563eb', color: '#fff',
125...             border: 'none', borderRadius: 8, cursor: 'pointer', fontSize: 13,
126...           }}
127...         >
128...           Send
129...         </button>
130...       </div>
131...     </div>
132...   );
133... }
134... 
135... const bubbleStyle: React.CSSProperties = {
136...   display: 'inline-block', maxWidth: '100%', padding: '10px 14px', borderRadius: 12,
137...   background: '#f3f4f6', color: '#1f2937', fontSize: 13, lineHeight: 1.6,
138... };
139... 
140... function BlockRenderer({ blocks }: { blocks: ContentBlock[] }) {
141...   const thinking = blocks.filter(b => b.type === 'thinking').map(b => (b as { type: 'thinking'; text: string }).text).join('\n\n');
142...   const visible = blocks.filter(b => b.type !== 'thinking');
143... 
144...   return (
145...     <>
146...       {visible.map((block, i) => {
147...         switch (block.type) {
148...           case 'text':
149...             return (
150...               <div key={i} style={{ ...bubbleStyle, marginBottom: 8 }}>
151...                 <div className="agent-markdown"><Markdown>{block.text}</Markdown></div>
152...                 {thinking && i === visible.length - 1 && (
153...                   <details style={{ marginTop: 8, borderTop: '1px solid #e5e7eb', paddingTop: 8 }}>
154...                     <summary style={{ cursor: 'pointer', fontSize: 11, color: '#6b7280', userSelect: 'none' }}>
155...                       Show reasoning
156...                     </summary>
157...                     <div style={{ fontSize: 12, color: '#6b7280', marginTop: 6, whiteSpace: 'pre-wrap' }}>{thinking}</div>
158...                   </details>
159...                 )}
160...               </div>
161...             );
162...           case 'table':
163...             return <AgentTable key={i} title={block.title} columns={block.columns} rows={block.rows} />;
164...           case 'chart':
165...             return <AgentChart key={i} spec={block.spec} />;
166...           default:
167...             return null;
168...         }
169...       })}
170...     </>
171...   );
172... }
173... 
174... function AgentTable({ title, columns, rows }: { title: string; columns: string[]; rows: string[][] }) {
175...   return (
176...     <div style={{ marginBottom: 8, borderRadius: 8, border: '1px solid #e5e7eb', overflow: 'hidden', background: '#fff' }}>
177...       {title && <div style={{ padding: '8px 12px', fontSize: 12, fontWeight: 600, color: '#374151', borderBottom: '1px solid #e5e7eb', background: '#f9fafb' }}>{title}</div>}
178...       <div style={{ overflowX: 'auto' }}>
179...         <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 12 }}>
180...           <thead>
181...             <tr>
182...               {columns.map((col, i) => (
183...                 <th key={i} style={{ padding: '6px 10px', textAlign: 'left', fontWeight: 600, color: '#374151', borderBottom: '2px solid #e5e7eb', background: '#f9fafb', whiteSpace: 'nowrap' }}>
184...                   {col}
185...                 </th>
186...               ))}
187...             </tr>
188...           </thead>
189...           <tbody>
190...             {rows.map((row, ri) => (
191...               <tr key={ri} style={{ borderBottom: '1px solid #f3f4f6' }}>
192...                 {row.map((cell, ci) => (
193...                   <td key={ci} style={{ padding: '5px 10px', whiteSpace: 'nowrap', color: '#1f2937' }}>
194...                     {formatCell(cell, columns[ci])}
195...                   </td>
196...                 ))}
197...               </tr>
198...             ))}
199...           </tbody>
200...         </table>
201...       </div>
202...     </div>
203...   );
204... }
205... 
206... function formatCell(val: string, _col: string): string {
207...   if (val === null || val === undefined) return '-';
208...   const num = Number(val);
209...   if (!isNaN(num) && val.trim() !== '') {
210...     if (Math.abs(num) >= 1000) return num.toLocaleString(undefined, { maximumFractionDigits: 2 });
211...     if (val.includes('.')) return num.toFixed(2);
212...   }
213...   return val;
214... }
215... 
216... function AgentChart({ spec }: { spec: string }) {
217...   const containerRef = useRef<HTMLDivElement>(null);
218... 
219...   useEffect(() => {
220...     let cancelled = false;
221...     async function render() {
222...       if (!containerRef.current) return;
223...       try {
224...         const vegaEmbed = (await import('vega-embed')).default;
225...         const parsed = JSON.parse(spec);
226...         // Make chart responsive to container width
227...         parsed.width = 'container';
228...         if (!parsed.height) parsed.height = 240;
229...         parsed.autosize = { type: 'fit', contains: 'padding' };
230...         // Clean up the chart styling
231...         parsed.config = {
232...           ...parsed.config,
233...           background: 'transparent',
234...           font: 'system-ui, sans-serif',
235...           axis: { labelFontSize: 11, titleFontSize: 12, gridColor: '#f0f0f0', domainColor: '#d1d5db', tickColor: '#d1d5db' },
236...           legend: { labelFontSize: 11, titleFontSize: 12 },
237...           view: { stroke: 'transparent' },
238...           range: { category: ['#2563eb', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#06b6d4'] },
239...         };
240...         if (!cancelled) {
241...           await vegaEmbed(containerRef.current, parsed, {
242...             actions: false,
243...             renderer: 'svg',
244...           });
245...         }
246...       } catch (err) {
247...         if (!cancelled && containerRef.current) {
248...           containerRef.current.textContent = `Chart error: ${err instanceof Error ? err.message : 'Unknown'}`;
249...         }
250...       }
251...     }
252...     render();
253...     return () => { cancelled = true; };
254...   }, [spec]);
255... 
256...   return (
257...     <div style={{ marginBottom: 8, borderRadius: 8, border: '1px solid #e5e7eb', overflow: 'hidden', background: '#fff', padding: '12px 12px 4px' }}>
258...       <div ref={containerRef} style={{ width: '100%' }} />
259...     </div>
260...   );
261... }
262... 