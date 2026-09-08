1... import { useEffect, useState } from 'react';
2... import { PieChart, Pie, Cell, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
3... import { executeSQL } from '../api/snowflake';
4... 
5... interface SegmentData {
6...   SEGMENT_LABEL: string;
7...   CUSTOMERS: number;
8...   AVG_REPURCHASE_SCORE: number;
9...   AVG_LTV: number;
10... }
11... 
12... interface CustomerRow {
13...   CUSTOMER_ID: string;
14...   SCORE: number;
15...   LTV: number;
16...   SEGMENT_LABEL: string;
17... }
18... 
19... const COLORS = ['#10b981', '#3b82f6', '#f59e0b', '#ef4444'];
20... 
21... type SortKey = 'CUSTOMER_ID' | 'SCORE' | 'LTV' | 'SEGMENT_LABEL';
22... 
23... export default function CustomerIntelligence() {
24...   const [segments, setSegments] = useState<SegmentData[]>([]);
25...   const [customers, setCustomers] = useState<CustomerRow[]>([]);
26...   const [sortKey, setSortKey] = useState<SortKey>('LTV');
27...   const [sortAsc, setSortAsc] = useState(false);
28...   const [segmentFilter, setSegmentFilter] = useState<string>('All');
29... 
30...   useEffect(() => { loadData(); }, []);
31... 
32...   async function loadData() {
33...     const [segData, custData] = await Promise.all([
34...       executeSQL(`
35...         SELECT SEGMENT_LABEL, COUNT(*) AS CUSTOMERS,
36...                ROUND(AVG(REPURCHASE_SCORE), 3) AS AVG_REPURCHASE_SCORE,
37...                ROUND(AVG(LTV_PREDICTION), 2) AS AVG_LTV
38...         FROM SB_COMMAND_CENTER.SCORING.CUSTOMER_SCORES
39...         GROUP BY 1 ORDER BY AVG_REPURCHASE_SCORE DESC
40...       `),
41...       executeSQL(`
42...         SELECT CUSTOMER_ID, ROUND(REPURCHASE_SCORE, 3) AS SCORE,
43...                ROUND(LTV_PREDICTION, 2) AS LTV, SEGMENT_LABEL
44...         FROM SB_COMMAND_CENTER.SCORING.CUSTOMER_SCORES
45...         ORDER BY LTV_PREDICTION DESC LIMIT 50
46...       `),
47...     ]);
48... 
49...     setSegments((segData as Record<string, string>[]).map(r => ({
50...       SEGMENT_LABEL: r.SEGMENT_LABEL,
51...       CUSTOMERS: Number(r.CUSTOMERS),
52...       AVG_REPURCHASE_SCORE: Number(r.AVG_REPURCHASE_SCORE),
53...       AVG_LTV: Number(r.AVG_LTV),
54...     })));
55... 
56...     setCustomers((custData as Record<string, string>[]).map(r => ({
57...       CUSTOMER_ID: r.CUSTOMER_ID,
58...       SCORE: Number(r.SCORE),
59...       LTV: Number(r.LTV),
60...       SEGMENT_LABEL: r.SEGMENT_LABEL,
61...     })));
62...   }
63... 
64...   function handleSort(key: SortKey) {
65...     if (key === sortKey) {
66...       setSortAsc(!sortAsc);
67...     } else {
68...       setSortKey(key);
69...       setSortAsc(key === 'CUSTOMER_ID' || key === 'SEGMENT_LABEL');
70...     }
71...   }
72... 
73...   const filtered = segmentFilter === 'All' ? customers : customers.filter(c => c.SEGMENT_LABEL === segmentFilter);
74...   const sorted = [...filtered].sort((a, b) => {
75...     const av = a[sortKey], bv = b[sortKey];
76...     const cmp = typeof av === 'number' ? (av as number) - (bv as number) : String(av).localeCompare(String(bv));
77...     return sortAsc ? cmp : -cmp;
78...   });
79... 
80...   const arrow = (key: SortKey) => sortKey === key ? (sortAsc ? ' \u25B2' : ' \u25BC') : '';
81...   const thStyle = (align: string): React.CSSProperties => ({
82...     textAlign: align as 'left' | 'right', padding: 8, cursor: 'pointer', userSelect: 'none',
83...   });
84... 
85...   return (
86...     <div>
87...       <h1 style={{ fontSize: 22, marginBottom: 16 }}>Customer Intelligence</h1>
88... 
89...       <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20, marginBottom: 24 }}>
90...         <div style={{ background: '#fff', borderRadius: 8, padding: 20, boxShadow: '0 1px 3px rgba(0,0,0,0.1)' }}>
91...           <h3 style={{ fontSize: 14, color: '#666', marginBottom: 12 }}>Segment Distribution</h3>
92...           <ResponsiveContainer width="100%" height={250}>
93...             <PieChart>
94...               <Pie data={segments} dataKey="CUSTOMERS" nameKey="SEGMENT_LABEL" cx="50%" cy="50%" outerRadius={90}
95...                 label={({ SEGMENT_LABEL, percent }) => `${SEGMENT_LABEL} (${(percent * 100).toFixed(0)}%)`}>
96...                 {segments.map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
97...               </Pie>
98...               <Tooltip formatter={(v: number) => v.toLocaleString()} />
99...               <Legend />
100...             </PieChart>
101...           </ResponsiveContainer>
102...         </div>
103... 
104...         <div style={{ background: '#fff', borderRadius: 8, padding: 20, boxShadow: '0 1px 3px rgba(0,0,0,0.1)' }}>
105...           <h3 style={{ fontSize: 14, color: '#666', marginBottom: 12 }}>Avg LTV by Segment</h3>
106...           <ResponsiveContainer width="100%" height={250}>
107...             <BarChart data={segments}>
108...               <CartesianGrid strokeDasharray="3 3" />
109...               <XAxis dataKey="SEGMENT_LABEL" tick={{ fontSize: 11 }} />
110...               <YAxis tick={{ fontSize: 11 }} tickFormatter={v => `$${v.toLocaleString()}`} />
111...               <Tooltip formatter={(v: number) => `$${v.toLocaleString()}`} />
112...               <Bar dataKey="AVG_LTV" fill="#3b82f6" radius={[4, 4, 0, 0]} />
113...             </BarChart>
114...           </ResponsiveContainer>
115...         </div>
116...       </div>
117... 
118...       <div style={{ background: '#fff', borderRadius: 8, padding: 20, boxShadow: '0 1px 3px rgba(0,0,0,0.1)' }}>
119...         <h3 style={{ fontSize: 14, color: '#666', marginBottom: 12 }}>Top Customers by LTV (click headers to sort)</h3>
120...         <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
121...           <thead>
122...             <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
123...               <th style={thStyle('left')} onClick={() => handleSort('CUSTOMER_ID')}>Customer ID{arrow('CUSTOMER_ID')}</th>
124...               <th style={thStyle('right')} onClick={() => handleSort('SCORE')}>Repurchase Score{arrow('SCORE')}</th>
125...               <th style={thStyle('right')} onClick={() => handleSort('LTV')}>LTV{arrow('LTV')}</th>
126...               <th style={thStyle('left')}>
127...                 <span style={{ cursor: 'pointer' }} onClick={() => handleSort('SEGMENT_LABEL')}>Segment{arrow('SEGMENT_LABEL')}</span>
128...                 <select value={segmentFilter} onChange={e => setSegmentFilter(e.target.value)}
129...                   style={{ marginLeft: 6, padding: '2px 4px', borderRadius: 4, border: '1px solid #ccc', fontSize: 11 }}>
130...                   <option value="All">All</option>
131...                   {segments.map(s => <option key={s.SEGMENT_LABEL} value={s.SEGMENT_LABEL}>{s.SEGMENT_LABEL}</option>)}
132...                 </select>
133...               </th>
134...             </tr>
135...           </thead>
136...           <tbody>
137...             {sorted.map((c, i) => (
138...               <tr key={i} style={{ borderBottom: '1px solid #f3f4f6' }}>
139...                 <td style={{ padding: 8 }}>{c.CUSTOMER_ID}</td>
140...                 <td style={{ padding: 8, textAlign: 'right' }}>{c.SCORE.toFixed(3)}</td>
141...                 <td style={{ padding: 8, textAlign: 'right' }}>${c.LTV.toLocaleString()}</td>
142...                 <td style={{ padding: 8 }}>{c.SEGMENT_LABEL}</td>
143...               </tr>
144...             ))}
145...           </tbody>
146...         </table>
147...       </div>
148...     </div>
149...   );
150... }
151... 