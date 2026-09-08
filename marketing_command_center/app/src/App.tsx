1... import { BrowserRouter, Routes, Route, NavLink } from 'react-router-dom';
2... import { useState } from 'react';
3... import ForecastDashboard from './pages/ForecastDashboard';
4... import CustomerIntelligence from './pages/CustomerIntelligence';
5... import LookalikeBuilder from './pages/LookalikeBuilder';
6... import ModelRegistry from './pages/ModelRegistry';
7... import AgentChat from './components/AgentChat';
8... 
9... export default function App() {
10...   const [chatOpen, setChatOpen] = useState(false);
11... 
12...   return (
13...     <BrowserRouter>
14...       <div style={{ display: 'flex', height: '100vh' }}>
15...         {/* Sidebar nav */}
16...         <nav style={{
17...           width: 230, background: 'linear-gradient(180deg, #0f172a 0%, #1e293b 100%)',
18...           padding: '24px 0', flexShrink: 0, display: 'flex', flexDirection: 'column',
19...         }}>
20...           <div style={{ padding: '0 20px', marginBottom: 32 }}>
21...             <div style={{ fontSize: 11, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 1.2, color: '#64748b', marginBottom: 6 }}>
22...               Summit Brands
23...             </div>
24...             <div style={{ fontSize: 15, fontWeight: 600, color: '#f1f5f9', lineHeight: 1.3 }}>
25...               Marketing<br />Command Center
26...             </div>
27...           </div>
28... 
29...           <div style={{ flex: 1 }}>
30...             <NavItem to="/" icon="chart">Forecast Dashboard</NavItem>
31...             <NavItem to="/customers" icon="users">Customer Intelligence</NavItem>
32...             <NavItem to="/lookalike" icon="target">Lookalike Builder</NavItem>
33...             <NavItem to="/agent" icon="message">Agent Chat</NavItem>
34...           </div>
35... 
36...           <div style={{ padding: '0 8px', marginBottom: 8 }}>
37...             <NavItem to="/models" icon="box">Model Registry</NavItem>
38...           </div>
39...         </nav>
40... 
41...         {/* Main content */}
42...         <main style={{ flex: 1, overflow: 'auto', padding: '24px 32px', background: '#f5f7fa', minWidth: 0 }}>
43...           <Routes>
44...             <Route path="/" element={<ForecastDashboard />} />
45...             <Route path="/customers" element={<CustomerIntelligence />} />
46...             <Route path="/lookalike" element={<LookalikeBuilder />} />
47...             <Route path="/models" element={<ModelRegistry />} />
48...             <Route path="/agent" element={<AgentFullPage />} />
49...           </Routes>
50...         </main>
51... 
52...         {/* Floating agent FAB */}
53...         <button
54...           onClick={() => setChatOpen(!chatOpen)}
55...           style={{
56...             position: 'fixed', bottom: 24, right: 24, width: 52, height: 52,
57...             borderRadius: '50%', border: 'none', cursor: 'pointer',
58...             background: chatOpen ? '#1e293b' : '#2563eb',
59...             color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center',
60...             boxShadow: '0 4px 12px rgba(0,0,0,0.2)', zIndex: 1000,
61...             transition: 'background 0.2s, transform 0.2s',
62...           }}
63...           onMouseEnter={e => (e.currentTarget.style.transform = 'scale(1.08)')}
64...           onMouseLeave={e => (e.currentTarget.style.transform = 'scale(1)')}
65...         >
66...           {chatOpen ? (
67...             <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
68...           ) : (
69...             <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
70...           )}
71...         </button>
72... 
73...         {/* Floating chat popover */}
74...         {chatOpen && (
75...           <div style={{
76...             position: 'fixed', bottom: 88, right: 24, width: 420, height: 560,
77...             borderRadius: 16, overflow: 'hidden', background: '#fff', zIndex: 999,
78...             boxShadow: '0 8px 30px rgba(0,0,0,0.18), 0 0 0 1px rgba(0,0,0,0.05)',
79...             display: 'flex', flexDirection: 'column',
80...             animation: 'fadeInUp 0.2s ease-out',
81...           }}>
82...             <AgentChat />
83...           </div>
84...         )}
85...       </div>
86...     </BrowserRouter>
87...   );
88... }
89... 
90... function AgentFullPage() {
91...   const [threads, setThreads] = useState<{ id: number; title: string; active: boolean }[]>([]);
92...   const [activeThread, setActiveThread] = useState(0);
93...   const [triggerMsg, setTriggerMsg] = useState<string | undefined>();
94... 
95...   const suggestions = [
96...     'What are the top-selling brands at Walmart this week?',
97...     'Compare forecast accuracy across all retailers',
98...     'Which customer segments have the highest LTV?',
99...     'Show me POS sales trends for Peak Hydro over the last 12 weeks',
100...     'Week-over-week growth of all brands at Target',
101...     'What is the average repurchase score by segment?',
102...   ];
103... 
104...   function startNew(msg?: string) {
105...     const id = Date.now();
106...     setThreads(prev => prev.map(t => ({ ...t, active: false })).concat({ id, title: msg || 'New chat', active: true }));
107...     setActiveThread(id);
108...     setTriggerMsg(msg);
109...   }
110... 
111...   function selectThread(id: number) {
112...     setActiveThread(id);
113...     setThreads(prev => prev.map(t => ({ ...t, active: t.id === id })));
114...     setTriggerMsg(undefined);
115...   }
116... 
117...   function handleFirstMessage(text: string) {
118...     setThreads(prev => prev.map(t => t.id === activeThread ? { ...t, title: text.substring(0, 50) } : t));
119...   }
120... 
121...   return (
122...     <div style={{ maxWidth: 1280, margin: '0 auto', height: 'calc(100vh - 48px)', display: 'flex', flexDirection: 'column' }}>
123...       <div style={{ marginBottom: 16 }}>
124...         <h1 style={{ fontSize: 22, marginBottom: 4 }}>Agent Chat</h1>
125...         <p style={{ fontSize: 13, color: '#6b7280', margin: 0 }}>
126...           Ask questions about demand forecasts, customer segments, POS sell-through, and marketing analytics.
127...         </p>
128...       </div>
129... 
130...       <div style={{ display: 'flex', gap: 16, flex: 1, minHeight: 0 }}>
131...         {/* Threads sidebar */}
132...         <div style={{ width: 240, flexShrink: 0, display: 'flex', flexDirection: 'column' }}>
133...           <button onClick={() => startNew()} style={{
134...             width: '100%', padding: '8px 12px', marginBottom: 8, borderRadius: 6, border: '1px solid #d1d5db',
135...             background: '#fff', fontSize: 12, cursor: 'pointer', fontWeight: 500, color: '#374151',
136...           }}>
137...             + New Chat
138...           </button>
139...           <div style={{ flex: 1, overflow: 'auto' }}>
140...             {threads.slice().reverse().map(t => (
141...               <div key={t.id} onClick={() => selectThread(t.id)} style={{
142...                 padding: '8px 10px', marginBottom: 2, borderRadius: 6, fontSize: 12, cursor: 'pointer',
143...                 background: t.active ? '#eff6ff' : 'transparent',
144...                 color: t.active ? '#1d4ed8' : '#6b7280',
145...                 fontWeight: t.active ? 500 : 400,
146...                 overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
147...               }}>
148...                 {t.title}
149...               </div>
150...             ))}
151...             {threads.length === 0 && (
152...               <p style={{ fontSize: 11, color: '#9ca3af', textAlign: 'center', marginTop: 20 }}>
153...                 No conversations yet
154...               </p>
155...             )}
156...           </div>
157...         </div>
158... 
159...         {/* Main chat */}
160...         <div style={{
161...           flex: 1, background: '#fff', borderRadius: 12,
162...           boxShadow: '0 1px 3px rgba(0,0,0,0.08), 0 0 0 1px rgba(0,0,0,0.03)',
163...           overflow: 'hidden', display: 'flex', flexDirection: 'column', minWidth: 0,
164...         }}>
165...           {activeThread ? (
166...             <AgentChat key={activeThread} initialMessage={triggerMsg} onFirstMessage={handleFirstMessage} />
167...           ) : (
168...             <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#9ca3af', fontSize: 14 }}>
169...               Start a new chat or select a conversation
170...             </div>
171...           )}
172...         </div>
173... 
174...         {/* Suggestions sidebar */}
175...         <div style={{ width: 220, flexShrink: 0 }}>
176...           <div style={{
177...             background: '#fff', borderRadius: 12, padding: 16,
178...             boxShadow: '0 1px 3px rgba(0,0,0,0.08), 0 0 0 1px rgba(0,0,0,0.03)',
179...           }}>
180...             <div style={{ fontSize: 12, fontWeight: 600, color: '#374151', marginBottom: 10 }}>Try asking</div>
181...             {suggestions.map((s, i) => (
182...               <div key={i} onClick={() => startNew(s)} style={{
183...                 padding: '8px 10px', marginBottom: 6, borderRadius: 6, fontSize: 12, color: '#374151',
184...                 background: '#f9fafb', border: '1px solid #f3f4f6', cursor: 'pointer', lineHeight: 1.4,
185...                 transition: 'background 0.1s',
186...               }}
187...               onMouseEnter={e => (e.currentTarget.style.background = '#eff6ff')}
188...               onMouseLeave={e => (e.currentTarget.style.background = '#f9fafb')}
189...               >
190...                 {s}
191...               </div>
192...             ))}
193...           </div>
194...         </div>
195...       </div>
196...     </div>
197...   );
198... }
199... 
200... const svgIcons: Record<string, React.ReactNode> = {
201...   chart: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/></svg>,
202...   users: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>,
203...   target: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="6"/><circle cx="12" cy="12" r="2"/></svg>,
204...   box: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><polyline points="3.27 6.96 12 12.01 20.73 6.96"/><line x1="12" y1="22.08" x2="12" y2="12"/></svg>,
205...   message: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>,
206... };
207... 
208... function NavItem({ to, icon, children }: { to: string; icon: string; children: React.ReactNode }) {
209...   return (
210...     <NavLink
211...       to={to}
212...       style={({ isActive }) => ({
213...         display: 'flex', alignItems: 'center', gap: 10,
214...         padding: '10px 20px', margin: '2px 8px', borderRadius: 6,
215...         color: isActive ? '#fff' : '#94a3b8',
216...         background: isActive ? 'rgba(59,130,246,0.15)' : 'transparent',
217...         textDecoration: 'none', fontSize: 13, fontWeight: isActive ? 500 : 400,
218...         transition: 'all 0.15s',
219...       })}
220...     >
221...       <span style={{ width: 20, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{svgIcons[icon]}</span>
222...       {children}
223...     </NavLink>
224...   );
225... }
226... 