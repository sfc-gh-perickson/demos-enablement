1... import { useState, useEffect, useRef } from 'react';
2... import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Cell } from 'recharts';
3... import { executeSQL } from '../api/snowflake';
4... import FeatureSelector, { AVAILABLE_FEATURES } from '../components/FeatureSelector';
5... 
6... const SEGMENTS = ['Champion', 'Engaged', 'Moderate', 'At Risk'];
7... const BRANDS = ['Peak Hydro', 'ChefLine', 'Ridgeline', 'VitaCare', 'PrimeLine'];
8... const STATES = ['CA', 'FL', 'GA', 'IL', 'NC', 'NY', 'OH', 'PA', 'TX', 'WA'];
9... 
10... const card: React.CSSProperties = { background: '#fff', borderRadius: 8, padding: 20, marginBottom: 16, boxShadow: '0 1px 3px rgba(0,0,0,0.1)' };
11... const thSort: React.CSSProperties = { textAlign: 'left', padding: 6, cursor: 'pointer', userSelect: 'none', whiteSpace: 'nowrap' };
12... const chip = (active: boolean): React.CSSProperties => ({
13...   display: 'inline-block', padding: '4px 10px', margin: '3px 4px 3px 0', borderRadius: 14, fontSize: 12, cursor: 'pointer',
14...   border: active ? '2px solid #2563eb' : '1px solid #d1d5db', background: active ? '#eff6ff' : '#fff', fontWeight: active ? 600 : 400,
15... });
16... 
17... interface ModelResult {
18...   model_name: string;
19...   auc: number;
20...   cv_fold_scores: number[];
21...   seed_count: number;
22...   total_scored: number;
23...   feature_importances: { feature: string; importance: number }[];
24...   score_distribution: { bucket: string; count: number }[];
25...   top_lookalikes: { customer_id: string; score: number }[];
26... }
27... 
28... interface CustomerProfile {
29...   customer_id: string;
30...   segment: string;
31...   ltv: number;
32...   repurchase: number;
33...   orders: number;
34...   spend: number;
35...   top_brand: string;
36...   state: string;
37... }
38... 
39... export default function LookalikeBuilder() {
40...   const [selSegments, setSelSegments] = useState<string[]>(['Champion']);
41...   const [selBrands, setSelBrands] = useState<string[]>([]);
42...   const [selStates, setSelStates] = useState<string[]>([]);
43...   const [minPurchases, setMinPurchases] = useState(2);
44...   const [minSpend, setMinSpend] = useState(50);
45...   const [seedCount, setSeedCount] = useState<number | null>(null);
46...   const [selectedFeatures, setSelectedFeatures] = useState<string[]>(AVAILABLE_FEATURES.map(f => f.name));
47...   const [modelName, setModelName] = useState('my_lookalike');
48...   const [loading, setLoading] = useState(false);
49...   const [status, setStatus] = useState('');
50...   const [result, setResult] = useState<ModelResult | null>(null);
51...   const [profiles, setProfiles] = useState<Map<string, CustomerProfile>>(new Map());
52...   const [sortKey, setSortKey] = useState<string>('score');
53...   const [sortAsc, setSortAsc] = useState(false);
54... 
55...   function toggle<T>(arr: T[], val: T): T[] {
56...     return arr.includes(val) ? arr.filter(v => v !== val) : [...arr, val];
57...   }
58... 
59...   function buildSeedSQL(mode: 'count' | 'ids'): string {
60...     const select = mode === 'count' ? 'COUNT(DISTINCT cs.CUSTOMER_ID) AS CNT' : 'DISTINCT cs.CUSTOMER_ID';
61...     const brandFilter = selBrands.length > 0 ? `AND BRAND IN (${selBrands.map(b => `'${b}'`).join(',')})` : '';
62...     const stateFilter = selStates.length > 0 ? `AND STATE IN (${selStates.map(s => `'${s}'`).join(',')})` : '';
63...     const segFilter = selSegments.length > 0 ? `AND cs.SEGMENT_LABEL IN (${selSegments.map(s => `'${s}'`).join(',')})` : '';
64... 
65...     return `
66...       SELECT ${select}
67...       FROM SB_COMMAND_CENTER.SCORING.CUSTOMER_SCORES cs
68...       JOIN (
69...         SELECT CUSTOMER_ID, COUNT(*) AS purchases, SUM(PURCHASE_AMOUNT) AS total_spend
70...         FROM SB_COMMAND_CENTER.RAW.CUSTOMER_TRANSACTIONS
71...         WHERE 1=1 ${brandFilter} ${stateFilter}
72...         GROUP BY 1
73...         HAVING purchases >= ${minPurchases} AND total_spend >= ${minSpend}
74...       ) ct ON cs.CUSTOMER_ID = ct.CUSTOMER_ID
75...       WHERE 1=1 ${segFilter}
76...     `;
77...   }
78... 
79...   const seedSql = buildSeedSQL('count');
80...   const prevSqlRef = useRef(seedSql);
81... 
82...   useEffect(() => {
83...     prevSqlRef.current = seedSql;
84...     const t = setTimeout(async () => {
85...       try {
86...         const rows = await executeSQL(seedSql);
87...         if (prevSqlRef.current === seedSql) {
88...           setSeedCount(Number((rows[0] as Record<string, string>)?.CNT ?? 0));
89...         }
90...       } catch { setSeedCount(null); }
91...     }, 500);
92...     return () => clearTimeout(t);
93...   }, [seedSql]);
94... 
95...   async function buildLookalike() {
96...     setLoading(true);
97...     setStatus('Resolving seed audience...');
98...     setResult(null);
99...     try {
100...       const seedRows = await executeSQL(buildSeedSQL('ids'));
101...       const ids = (seedRows as Record<string, string>[]).map(r => r.CUSTOMER_ID);
102...       if (ids.length === 0) { setStatus('No customers match the seed criteria.'); setLoading(false); return; }
103...       if (ids.length > 5000) { setStatus(`Seed too large (${ids.length}). Narrow your filters.`); setLoading(false); return; }
104... 
105...       setStatus(`Training model on ${ids.length} seed customers...`);
106...       const idsArray = ids.map(id => `'${id}'`).join(',');
107...       const ts = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14);
108...       const fullModelName = `${modelName}_${ts}`;
109...       const viewNames = [...new Set(
110...         selectedFeatures.map(f => AVAILABLE_FEATURES.find(af => af.name === f)?.view).filter(Boolean)
111...       )];
112...       const fvs = viewNames.map(f => `'${f}'`).join(',');
113...       const procResult = await executeSQL(`
114...         CALL SB_COMMAND_CENTER.PROCEDURES.BUILD_LOOKALIKE(
115...           ARRAY_CONSTRUCT(${idsArray}),
116...           ARRAY_CONSTRUCT(${fvs}),
117...           '${fullModelName}'
118...         )
119...       `);
120... 
121...       const firstRow = procResult[0] as Record<string, string>;
122...       const jsonStr = firstRow ? Object.values(firstRow)[0] : null;
123...       if (jsonStr) {
124...         const parsed: ModelResult = JSON.parse(jsonStr);
125...         setResult(parsed);
126...         setStatus(`Model "${parsed.model_name}" built — AUC: ${parsed.auc.toFixed(3)}. Loading profiles...`);
127... 
128...         // Fetch profiles for the top lookalikes
129...         const topIds = parsed.top_lookalikes.map(l => `'${l.customer_id}'`).join(',');
130...         const profileRows = await executeSQL(`
131...           SELECT cs.CUSTOMER_ID, cs.SEGMENT_LABEL, cs.LTV_PREDICTION, cs.REPURCHASE_SCORE,
132...                  ct.ORDERS, ct.TOTAL_SPEND, ct.TOP_BRAND, ct.STATE
133...           FROM SB_COMMAND_CENTER.SCORING.CUSTOMER_SCORES cs
134...           LEFT JOIN (
135...             SELECT CUSTOMER_ID, COUNT(*) AS ORDERS, ROUND(SUM(PURCHASE_AMOUNT),2) AS TOTAL_SPEND,
136...                    MAX_BY(BRAND, PURCHASE_AMOUNT) AS TOP_BRAND,
137...                    MAX_BY(STATE, TRANSACTION_DATE) AS STATE
138...             FROM SB_COMMAND_CENTER.RAW.CUSTOMER_TRANSACTIONS
139...             GROUP BY 1
140...           ) ct ON cs.CUSTOMER_ID = ct.CUSTOMER_ID
141...           WHERE cs.CUSTOMER_ID IN (${topIds})
142...         `);
143...         const pMap = new Map<string, CustomerProfile>();
144...         for (const r of profileRows as Record<string, string>[]) {
145...           pMap.set(r.CUSTOMER_ID, {
146...             customer_id: r.CUSTOMER_ID,
147...             segment: r.SEGMENT_LABEL || '-',
148...             ltv: Number(r.LTV_PREDICTION) || 0,
149...             repurchase: Number(r.REPURCHASE_SCORE) || 0,
150...             orders: Number(r.ORDERS) || 0,
151...             spend: Number(r.TOTAL_SPEND) || 0,
152...             top_brand: r.TOP_BRAND || '-',
153...             state: r.STATE || '-',
154...           });
155...         }
156...         setProfiles(pMap);
157...         setStatus(`Model "${parsed.model_name}" built — AUC: ${parsed.auc.toFixed(3)}`);
158...       } else {
159...         setStatus('Model built but no stats returned.');
160...       }
161...     } catch (err) {
162...       setStatus(`Error: ${err instanceof Error ? err.message : 'Unknown error'}`);
163...     } finally {
164...       setLoading(false);
165...     }
166...   }
167... 
168...   function handleSort(key: string) {
169...     if (key === sortKey) setSortAsc(!sortAsc);
170...     else { setSortKey(key); setSortAsc(key === 'customer_id'); }
171...   }
172... 
173...   const sortedLookalikes = result ? [...result.top_lookalikes].sort((a, b) => {
174...     if (sortKey === 'score') return sortAsc ? a.score - b.score : b.score - a.score;
175...     if (sortKey === 'customer_id') return sortAsc ? a.customer_id.localeCompare(b.customer_id) : b.customer_id.localeCompare(a.customer_id);
176...     const pa = profiles.get(a.customer_id);
177...     const pb = profiles.get(b.customer_id);
178...     if (!pa || !pb) return 0;
179...     const va = pa[sortKey as keyof CustomerProfile];
180...     const vb = pb[sortKey as keyof CustomerProfile];
181...     const cmp = typeof va === 'number' ? (va as number) - (vb as number) : String(va).localeCompare(String(vb));
182...     return sortAsc ? cmp : -cmp;
183...   }) : [];
184... 
185...   const arrow = (key: string) => sortKey === key ? (sortAsc ? ' \u25B2' : ' \u25BC') : '';
186...   const aucColor = (auc: number) => auc >= 0.8 ? '#10b981' : auc >= 0.7 ? '#f59e0b' : '#ef4444';
187... 
188...   const canBuild = selSegments.length > 0 && selectedFeatures.length > 0 && seedCount !== null && seedCount > 0;
189... 
190...   return (
191...     <div>
192...       <h1 style={{ fontSize: 22, marginBottom: 16 }}>Lookalike Audience Builder</h1>
193...       <p style={{ color: '#666', fontSize: 13, marginBottom: 24 }}>
194...         Define a customer profile, select ML features, and build a model to find similar customers.
195...       </p>
196... 
197...       <div style={{ display: 'grid', gridTemplateColumns: '380px 1fr', gap: 24 }}>
198...         {/* Left column: filters */}
199...         <div>
200...           <div style={card}>
201...             <h3 style={{ fontSize: 14, marginBottom: 12 }}>1. Define Seed Profile</h3>
202... 
203...             <label style={{ fontSize: 12, fontWeight: 600, color: '#374151', display: 'block', marginBottom: 4 }}>Segment</label>
204...             <div style={{ marginBottom: 12 }}>
205...               {SEGMENTS.map(s => (
206...                 <span key={s} style={chip(selSegments.includes(s))} onClick={() => setSelSegments(toggle(selSegments, s))}>{s}</span>
207...               ))}
208...             </div>
209... 
210...             <label style={{ fontSize: 12, fontWeight: 600, color: '#374151', display: 'block', marginBottom: 4 }}>Brand Affinity</label>
211...             <div style={{ marginBottom: 12 }}>
212...               {BRANDS.map(b => (
213...                 <span key={b} style={chip(selBrands.includes(b))} onClick={() => setSelBrands(toggle(selBrands, b))}>{b}</span>
214...               ))}
215...             </div>
216... 
217...             <label style={{ fontSize: 12, fontWeight: 600, color: '#374151', display: 'block', marginBottom: 4 }}>State</label>
218...             <div style={{ marginBottom: 12 }}>
219...               {STATES.map(s => (
220...                 <span key={s} style={chip(selStates.includes(s))} onClick={() => setSelStates(toggle(selStates, s))}>{s}</span>
221...               ))}
222...             </div>
223... 
224...             <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 12 }}>
225...               <div>
226...                 <label style={{ fontSize: 12, fontWeight: 600, color: '#374151' }}>Min Purchases</label>
227...                 <input type="number" value={minPurchases} onChange={e => setMinPurchases(Number(e.target.value))}
228...                   style={{ width: '100%', padding: 8, border: '1px solid #ddd', borderRadius: 6, fontSize: 13, marginTop: 4 }} />
229...               </div>
230...               <div>
231...                 <label style={{ fontSize: 12, fontWeight: 600, color: '#374151' }}>Min Spend ($)</label>
232...                 <input type="number" value={minSpend} onChange={e => setMinSpend(Number(e.target.value))}
233...                   style={{ width: '100%', padding: 8, border: '1px solid #ddd', borderRadius: 6, fontSize: 13, marginTop: 4 }} />
234...               </div>
235...             </div>
236... 
237...             <div style={{ padding: '8px 12px', background: '#f9fafb', borderRadius: 6, fontSize: 13, textAlign: 'center' }}>
238...               {seedCount === null ? 'Counting...' : <><strong>{seedCount.toLocaleString()}</strong> customers match this profile</>}
239...             </div>
240...           </div>
241... 
242...           <div style={card}>
243...             <h3 style={{ fontSize: 14, marginBottom: 12 }}>2. Select Features</h3>
244...             <FeatureSelector selected={selectedFeatures} onChange={setSelectedFeatures} />
245...           </div>
246... 
247...           <div style={card}>
248...             <h3 style={{ fontSize: 14, marginBottom: 12 }}>3. Model Name</h3>
249...             <input value={modelName} onChange={e => setModelName(e.target.value)}
250...               style={{ width: '100%', padding: 10, border: '1px solid #ddd', borderRadius: 6, fontSize: 13 }} />
251...           </div>
252... 
253...           <button onClick={buildLookalike} disabled={loading || !canBuild}
254...             style={{
255...               width: '100%', padding: '12px 24px', background: loading ? '#94a3b8' : !canBuild ? '#cbd5e1' : '#2563eb',
256...               color: '#fff', border: 'none', borderRadius: 8, cursor: loading || !canBuild ? 'default' : 'pointer',
257...               fontSize: 14, fontWeight: 500,
258...             }}>
259...             {loading ? 'Training...' : 'Build Lookalike Model'}
260...           </button>
261...           {status && <p style={{ marginTop: 12, fontSize: 13, color: '#666' }}>{status}</p>}
262...         </div>
263... 
264...         {/* Right column: results */}
265...         <div>
266...           {!result ? (
267...             <div style={{ ...card, textAlign: 'center', padding: 60, color: '#999' }}>
268...               <p style={{ fontSize: 14 }}>Define a seed profile and click Build to see model results.</p>
269...             </div>
270...           ) : (
271...             <>
272...               {/* Metric cards */}
273...               <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12, marginBottom: 16 }}>
274...                 <MetricCard label="AUC Score" value={result.auc.toFixed(3)} color={aucColor(result.auc)} />
275...                 <MetricCard label="Seed Size" value={result.seed_count.toLocaleString()} />
276...                 <MetricCard label="Scored" value={result.total_scored.toLocaleString()} />
277...                 <MetricCard label="Top Score" value={result.top_lookalikes[0]?.score.toFixed(4) ?? '-'} />
278...               </div>
279... 
280...               {/* CV Fold scores */}
281...               {result.cv_fold_scores && result.cv_fold_scores.length > 0 && (
282...                 <div style={{ ...card, marginBottom: 16 }}>
283...                   <h3 style={{ fontSize: 13, color: '#666', marginBottom: 4 }}>Cross-Validation AUC by Fold</h3>
284...                   <div style={{ display: 'flex', gap: 8 }}>
285...                     {result.cv_fold_scores.map((s, i) => (
286...                       <span key={i} style={{ fontSize: 12, padding: '4px 10px', background: '#f0fdf4', borderRadius: 6, color: '#166534' }}>
287...                         Fold {i + 1}: {s.toFixed(3)}
288...                       </span>
289...                     ))}
290...                   </div>
291...                 </div>
292...               )}
293... 
294...               {/* Charts row */}
295...               <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16, marginBottom: 16 }}>
296...                 {/* Feature importance */}
297...                 <div style={card}>
298...                   <h3 style={{ fontSize: 13, color: '#666', marginBottom: 8 }}>Feature Importance</h3>
299...                   <ResponsiveContainer width="100%" height={220}>
300...                     <BarChart data={result.feature_importances.slice(0, 8)} layout="vertical" margin={{ left: 10 }}>
301...                       <CartesianGrid strokeDasharray="3 3" />
302...                       <XAxis type="number" tick={{ fontSize: 10 }} />
303...                       <YAxis type="category" dataKey="feature" tick={{ fontSize: 10 }} width={120} />
304...                       <Tooltip formatter={(v: number) => v.toFixed(4)} />
305...                       <Bar dataKey="importance" radius={[0, 4, 4, 0]}>
306...                         {result.feature_importances.slice(0, 8).map((_, i) => (
307...                           <Cell key={i} fill={i === 0 ? '#2563eb' : i < 3 ? '#60a5fa' : '#93c5fd'} />
308...                         ))}
309...                       </Bar>
310...                     </BarChart>
311...                   </ResponsiveContainer>
312...                 </div>
313... 
314...                 {/* Score distribution */}
315...                 <div style={card}>
316...                   <h3 style={{ fontSize: 13, color: '#666', marginBottom: 8 }}>Lookalike Score Distribution</h3>
317...                   <ResponsiveContainer width="100%" height={220}>
318...                     <BarChart data={result.score_distribution}>
319...                       <CartesianGrid strokeDasharray="3 3" />
320...                       <XAxis dataKey="bucket" tick={{ fontSize: 10 }} />
321...                       <YAxis tick={{ fontSize: 10 }} />
322...                       <Tooltip />
323...                       <Bar dataKey="count" fill="#f59e0b" radius={[4, 4, 0, 0]} />
324...                     </BarChart>
325...                   </ResponsiveContainer>
326...                 </div>
327...               </div>
328... 
329...               {/* Results table */}
330...               <div style={card}>
331...                 <h3 style={{ fontSize: 13, color: '#666', marginBottom: 8 }}>Top {result.top_lookalikes.length} Lookalike Customers</h3>
332...                 <div style={{ overflowX: 'auto' }}>
333...                 <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 12 }}>
334...                   <thead>
335...                     <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
336...                       <th style={thSort} onClick={() => handleSort('customer_id')}>Customer{arrow('customer_id')}</th>
337...                       <th style={{ ...thSort, textAlign: 'right' }} onClick={() => handleSort('score')}>Score{arrow('score')}</th>
338...                       <th style={{ padding: 6, width: 100 }}>Confidence</th>
339...                       <th style={thSort} onClick={() => handleSort('segment')}>Segment{arrow('segment')}</th>
340...                       <th style={{ ...thSort, textAlign: 'right' }} onClick={() => handleSort('ltv')}>LTV{arrow('ltv')}</th>
341...                       <th style={{ ...thSort, textAlign: 'right' }} onClick={() => handleSort('repurchase')}>Repurchase{arrow('repurchase')}</th>
342...                       <th style={{ ...thSort, textAlign: 'right' }} onClick={() => handleSort('orders')}>Orders{arrow('orders')}</th>
343...                       <th style={{ ...thSort, textAlign: 'right' }} onClick={() => handleSort('spend')}>Spend{arrow('spend')}</th>
344...                       <th style={thSort} onClick={() => handleSort('top_brand')}>Top Brand{arrow('top_brand')}</th>
345...                       <th style={thSort} onClick={() => handleSort('state')}>State{arrow('state')}</th>
346...                     </tr>
347...                   </thead>
348...                   <tbody>
349...                     {sortedLookalikes.map((r, i) => {
350...                       const p = profiles.get(r.customer_id);
351...                       return (
352...                         <tr key={i} style={{ borderBottom: '1px solid #f3f4f6' }}>
353...                           <td style={{ padding: 6 }}>{r.customer_id}</td>
354...                           <td style={{ padding: 6, textAlign: 'right', fontFamily: 'monospace' }}>{r.score.toFixed(4)}</td>
355...                           <td style={{ padding: '6px 6px 6px 0' }}>
356...                             <div style={{ background: '#e5e7eb', borderRadius: 4, height: 14, overflow: 'hidden' }}>
357...                               <div style={{ width: `${(r.score * 100).toFixed(1)}%`, background: r.score > 0.8 ? '#10b981' : r.score > 0.5 ? '#f59e0b' : '#94a3b8', height: '100%', borderRadius: 4 }} />
358...                             </div>
359...                           </td>
360...                           <td style={{ padding: 6 }}>{p?.segment ?? '-'}</td>
361...                           <td style={{ padding: 6, textAlign: 'right' }}>{p ? `$${p.ltv.toFixed(0)}` : '-'}</td>
362...                           <td style={{ padding: 6, textAlign: 'right' }}>{p?.repurchase.toFixed(3) ?? '-'}</td>
363...                           <td style={{ padding: 6, textAlign: 'right' }}>{p?.orders ?? '-'}</td>
364...                           <td style={{ padding: 6, textAlign: 'right' }}>{p ? `$${p.spend.toFixed(0)}` : '-'}</td>
365...                           <td style={{ padding: 6 }}>{p?.top_brand ?? '-'}</td>
366...                           <td style={{ padding: 6 }}>{p?.state ?? '-'}</td>
367...                         </tr>
368...                       );
369...                     })}
370...                   </tbody>
371...                 </table>
372...                 </div>
373...               </div>
374...             </>
375...           )}
376...         </div>
377...       </div>
378...     </div>
379...   );
380... }
381... 
382... function MetricCard({ label, value, color }: { label: string; value: string; color?: string }) {
383...   return (
384...     <div style={{ background: '#fff', borderRadius: 8, padding: 16, boxShadow: '0 1px 3px rgba(0,0,0,0.1)', textAlign: 'center' }}>
385...       <div style={{ fontSize: 11, color: '#6b7280', marginBottom: 4 }}>{label}</div>
386...       <div style={{ fontSize: 22, fontWeight: 700, color: color || '#111827' }}>{value}</div>
387...     </div>
388...   );
389... }
390... 