1... import { useEffect, useState } from 'react';
2... import {
3...   LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend,
4...   ResponsiveContainer, Area, ComposedChart, Cell,
5... } from 'recharts';
6... import { executeSQL } from '../api/snowflake';
7... 
8... const card: React.CSSProperties = { background: '#fff', borderRadius: 8, padding: 20, boxShadow: '0 1px 3px rgba(0,0,0,0.1)' };
9... 
10... interface ChartPoint { date: string; label: string; actual?: number; forecast?: number; }
11... interface KPIs { lastWeekUnits: number; lastWeekRevenue: number; returnRate: number; markdownRate: number; forecastTotal: number; }
12... interface BrandRow { brand: string; units: number; revenue: number; wow: number; }
13... 
14... const RETAILERS = ['Walmart', 'Target', 'Ulta', 'Home Depot', 'Kohls'];
15... const BRANDS = ['Peak Hydro', 'ChefLine', 'Ridgeline', 'VitaCare', 'PrimeLine'];
16... 
17... export default function ForecastDashboard() {
18...   const [chartData, setChartData] = useState<ChartPoint[]>([]);
19...   const [kpis, setKpis] = useState<KPIs | null>(null);
20...   const [brandBreakdown, setBrandBreakdown] = useState<BrandRow[]>([]);
21...   const [selectedRetailer, setSelectedRetailer] = useState('Walmart');
22...   const [selectedBrand, setSelectedBrand] = useState('Peak Hydro');
23... 
24...   useEffect(() => { loadData(); }, [selectedRetailer, selectedBrand]);
25... 
26...   async function loadData() {
27...     const [fData, aData, kpiData, brandData] = await Promise.all([
28...       executeSQL(`
29...         SELECT FORECAST_DATE, ROUND(FORECASTED_UNITS) AS FORECASTED_UNITS
30...         FROM SB_COMMAND_CENTER.SCORING.DEMAND_FORECASTS
31...         WHERE RETAILER_NAME = '${selectedRetailer}' AND ITEM_BRAND = '${selectedBrand}'
32...         ORDER BY FORECAST_DATE
33...       `),
34...       executeSQL(`
35...         SELECT RETAILER_DATE, SUM(GROSS_AMT_SOLD_UNITS) AS GROSS_UNITS_SOLD
36...         FROM SB_COMMAND_CENTER.RAW.POS_SALES
37...         WHERE RETAILER_NAME = '${selectedRetailer}' AND ITEM_BRAND = '${selectedBrand}'
38...         GROUP BY RETAILER_DATE ORDER BY RETAILER_DATE DESC LIMIT 12
39...       `),
40...       executeSQL(`
41...         SELECT
42...           (SELECT SUM(GROSS_AMT_SOLD_UNITS) FROM SB_COMMAND_CENTER.RAW.POS_SALES
43...            WHERE RETAILER_NAME='${selectedRetailer}' AND ITEM_BRAND='${selectedBrand}'
44...              AND RETAILER_DATE = (SELECT MAX(RETAILER_DATE) FROM SB_COMMAND_CENTER.RAW.POS_SALES WHERE RETAILER_NAME='${selectedRetailer}' AND ITEM_BRAND='${selectedBrand}')
45...           ) AS LAST_WEEK_UNITS,
46...           (SELECT SUM(GROSS_SALES_RETAIL) FROM SB_COMMAND_CENTER.RAW.POS_SALES
47...            WHERE RETAILER_NAME='${selectedRetailer}' AND ITEM_BRAND='${selectedBrand}'
48...              AND RETAILER_DATE = (SELECT MAX(RETAILER_DATE) FROM SB_COMMAND_CENTER.RAW.POS_SALES WHERE RETAILER_NAME='${selectedRetailer}' AND ITEM_BRAND='${selectedBrand}')
49...           ) AS LAST_WEEK_REVENUE,
50...           ROUND(SUM(CUSTOMER_RETURN_UNITS) / NULLIF(SUM(GROSS_AMT_SOLD_UNITS), 0) * 100, 1) AS RETURN_RATE,
51...           ROUND(SUM(TOTAL_MARKDOWN) / NULLIF(SUM(GROSS_SALES_RETAIL), 0) * 100, 1) AS MARKDOWN_RATE
52...         FROM SB_COMMAND_CENTER.RAW.POS_SALES
53...         WHERE RETAILER_NAME = '${selectedRetailer}' AND ITEM_BRAND = '${selectedBrand}'
54...       `),
55...       executeSQL(`
56...         WITH latest AS (
57...           SELECT MAX(RETAILER_DATE) AS max_dt FROM SB_COMMAND_CENTER.RAW.POS_SALES WHERE RETAILER_NAME='${selectedRetailer}'
58...         ),
59...         curr AS (
60...           SELECT ITEM_BRAND, SUM(GROSS_AMT_SOLD_UNITS) AS units, SUM(GROSS_SALES_RETAIL) AS revenue
61...           FROM SB_COMMAND_CENTER.RAW.POS_SALES, latest
62...           WHERE RETAILER_NAME='${selectedRetailer}' AND RETAILER_DATE = max_dt GROUP BY 1
63...         ),
64...         prev AS (
65...           SELECT ITEM_BRAND, SUM(GROSS_SALES_RETAIL) AS revenue
66...           FROM SB_COMMAND_CENTER.RAW.POS_SALES, latest
67...           WHERE RETAILER_NAME='${selectedRetailer}' AND RETAILER_DATE = DATEADD(week, -1, max_dt) GROUP BY 1
68...         )
69...         SELECT c.ITEM_BRAND, c.units, c.revenue,
70...                ROUND((c.revenue - p.revenue) / NULLIF(p.revenue, 0) * 100, 1) AS WOW
71...         FROM curr c LEFT JOIN prev p ON c.ITEM_BRAND = p.ITEM_BRAND
72...         ORDER BY c.revenue DESC
73...       `),
74...     ]);
75... 
76...     // Chart data
77...     const byDate = new Map<string, ChartPoint>();
78...     for (const row of (aData as Record<string, string>[]).reverse()) {
79...       const d = toISODate(row.RETAILER_DATE);
80...       byDate.set(d, { date: d, label: formatDate(row.RETAILER_DATE), actual: Number(row.GROSS_UNITS_SOLD) });
81...     }
82...     let forecastTotal = 0;
83...     for (const row of fData as Record<string, string>[]) {
84...       const d = toISODate(row.FORECAST_DATE);
85...       const existing = byDate.get(d) || { date: d, label: formatDate(row.FORECAST_DATE) };
86...       existing.forecast = Number(row.FORECASTED_UNITS);
87...       forecastTotal += existing.forecast;
88...       byDate.set(d, existing);
89...     }
90...     const points = [...byDate.values()];
91...     const lastActualIdx = points.reduce((acc, p, i) => (p.actual !== undefined ? i : acc), -1);
92...     if (lastActualIdx >= 0 && lastActualIdx < points.length - 1 && points[lastActualIdx].forecast === undefined) {
93...       points[lastActualIdx].forecast = points[lastActualIdx].actual;
94...     }
95...     setChartData(points);
96... 
97...     // KPIs
98...     const k = kpiData[0] as Record<string, string> | undefined;
99...     if (k) {
100...       setKpis({
101...         lastWeekUnits: Number(k.LAST_WEEK_UNITS) || 0,
102...         lastWeekRevenue: Number(k.LAST_WEEK_REVENUE) || 0,
103...         returnRate: Number(k.RETURN_RATE) || 0,
104...         markdownRate: Number(k.MARKDOWN_RATE) || 0,
105...         forecastTotal,
106...       });
107...     }
108... 
109...     // Brand breakdown
110...     setBrandBreakdown((brandData as Record<string, string>[]).map(r => ({
111...       brand: r.ITEM_BRAND,
112...       units: Number(r.UNITS) || 0,
113...       revenue: Number(r.REVENUE) || 0,
114...       wow: Number(r.WOW) || 0,
115...     })));
116...   }
117... 
118...   return (
119...     <div>
120...       <h1 style={{ fontSize: 22, marginBottom: 16 }}>Demand Forecast Dashboard</h1>
121... 
122...       <div style={{ display: 'flex', gap: 12, marginBottom: 20 }}>
123...         <select value={selectedRetailer} onChange={e => setSelectedRetailer(e.target.value)}
124...           style={{ padding: '8px 12px', borderRadius: 6, border: '1px solid #ddd', fontSize: 13 }}>
125...           {RETAILERS.map(r => <option key={r} value={r}>{r}</option>)}
126...         </select>
127...         <select value={selectedBrand} onChange={e => setSelectedBrand(e.target.value)}
128...           style={{ padding: '8px 12px', borderRadius: 6, border: '1px solid #ddd', fontSize: 13 }}>
129...           {BRANDS.map(b => <option key={b} value={b}>{b}</option>)}
130...         </select>
131...       </div>
132... 
133...       {/* KPI Cards */}
134...       {kpis && (
135...         <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: 12, marginBottom: 20 }}>
136...           <KPI label="Last Week Units" value={kpis.lastWeekUnits.toLocaleString()} />
137...           <KPI label="Last Week Revenue" value={`$${(kpis.lastWeekRevenue / 1000).toFixed(0)}K`} />
138...           <KPI label="8-Wk Forecast" value={`${(kpis.forecastTotal / 1000).toFixed(0)}K units`} />
139...           <KPI label="Return Rate" value={`${kpis.returnRate}%`} color={kpis.returnRate > 6 ? '#ef4444' : '#10b981'} />
140...           <KPI label="Markdown Rate" value={`${kpis.markdownRate}%`} color={kpis.markdownRate > 6 ? '#f59e0b' : '#10b981'} />
141...         </div>
142...       )}
143... 
144...       {/* Main chart */}
145...       <div style={{ ...card, marginBottom: 20 }}>
146...         <h3 style={{ fontSize: 14, color: '#666', marginBottom: 12 }}>
147...           {selectedRetailer} &times; {selectedBrand} — Actual vs 8-Week Forecast
148...         </h3>
149...         <ResponsiveContainer width="100%" height={320}>
150...           <ComposedChart data={chartData}>
151...             <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
152...             <XAxis dataKey="label" tick={{ fontSize: 11 }} />
153...             <YAxis tick={{ fontSize: 11 }} tickFormatter={v => `${(v / 1000).toFixed(0)}K`} />
154...             <Tooltip
155...               labelFormatter={(_, payload) => payload?.[0]?.payload?.date || ''}
156...               formatter={(v: number) => v.toLocaleString()}
157...             />
158...             <Legend />
159...             <Area type="monotone" dataKey="actual" fill="#dbeafe" stroke="none" legendType="none" />
160...             <Line type="monotone" dataKey="actual" stroke="#2563eb" strokeWidth={2.5} dot={{ r: 3, fill: '#2563eb' }} name="Actual Units" connectNulls={false} />
161...             <Line type="monotone" dataKey="forecast" stroke="#f59e0b" strokeWidth={2.5} strokeDasharray="6 3" dot={{ r: 3, fill: '#f59e0b' }} name="Forecast" connectNulls={false} />
162...           </ComposedChart>
163...         </ResponsiveContainer>
164...       </div>
165... 
166...       {/* Brand breakdown for the retailer */}
167...       <div style={{ ...card }}>
168...         <h3 style={{ fontSize: 14, color: '#666', marginBottom: 12 }}>
169...           All Brands at {selectedRetailer} — Latest Week
170...         </h3>
171...         <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>
172...           <ResponsiveContainer width="100%" height={220}>
173...             <BarChart data={brandBreakdown} layout="vertical" margin={{ left: 10 }}>
174...               <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
175...               <XAxis type="number" tick={{ fontSize: 10 }} tickFormatter={v => `$${(v / 1000).toFixed(0)}K`} />
176...               <YAxis type="category" dataKey="brand" tick={{ fontSize: 11 }} width={90} />
177...               <Tooltip formatter={(v: number) => `$${v.toLocaleString()}`} />
178...               <Bar dataKey="revenue" radius={[0, 4, 4, 0]}>
179...                 {brandBreakdown.map((b, i) => (
180...                   <Cell key={i} fill={b.brand === selectedBrand ? '#2563eb' : '#93c5fd'} />
181...                 ))}
182...               </Bar>
183...             </BarChart>
184...           </ResponsiveContainer>
185...           <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 12, alignSelf: 'start' }}>
186...             <thead>
187...               <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
188...                 <th style={{ textAlign: 'left', padding: 8 }}>Brand</th>
189...                 <th style={{ textAlign: 'right', padding: 8 }}>Units</th>
190...                 <th style={{ textAlign: 'right', padding: 8 }}>Revenue</th>
191...                 <th style={{ textAlign: 'right', padding: 8 }}>WoW</th>
192...               </tr>
193...             </thead>
194...             <tbody>
195...               {brandBreakdown.map((b, i) => (
196...                 <tr key={i} style={{ borderBottom: '1px solid #f3f4f6', fontWeight: b.brand === selectedBrand ? 600 : 400 }}>
197...                   <td style={{ padding: 8 }}>{b.brand}</td>
198...                   <td style={{ padding: 8, textAlign: 'right' }}>{b.units.toLocaleString()}</td>
199...                   <td style={{ padding: 8, textAlign: 'right' }}>${(b.revenue / 1000).toFixed(0)}K</td>
200...                   <td style={{ padding: 8, textAlign: 'right', color: b.wow >= 0 ? '#10b981' : '#ef4444' }}>
201...                     {b.wow >= 0 ? '+' : ''}{b.wow}%
202...                   </td>
203...                 </tr>
204...               ))}
205...             </tbody>
206...           </table>
207...         </div>
208...       </div>
209...     </div>
210...   );
211... }
212... 
213... function KPI({ label, value, color }: { label: string; value: string; color?: string }) {
214...   return (
215...     <div style={{ background: '#fff', borderRadius: 8, padding: 16, boxShadow: '0 1px 3px rgba(0,0,0,0.1)', textAlign: 'center' }}>
216...       <div style={{ fontSize: 11, color: '#6b7280', marginBottom: 4 }}>{label}</div>
217...       <div style={{ fontSize: 20, fontWeight: 700, color: color || '#111827' }}>{value}</div>
218...     </div>
219...   );
220... }
221... 
222... function epochDaysToDate(val: string): Date {
223...   const days = parseInt(val, 10);
224...   if (!isNaN(days) && days > 10000 && days < 100000) return new Date(days * 86400000);
225...   return new Date(val + 'T00:00:00');
226... }
227... 
228... function formatDate(val: string): string {
229...   return epochDaysToDate(val).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
230... }
231... 
232... function toISODate(val: string): string {
233...   return epochDaysToDate(val).toISOString().slice(0, 10);
234... }
235... 