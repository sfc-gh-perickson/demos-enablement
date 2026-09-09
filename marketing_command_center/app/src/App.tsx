import { BrowserRouter, Routes, Route, NavLink } from 'react-router-dom';
import { useState } from 'react';
import ForecastDashboard from './pages/ForecastDashboard';
import CustomerIntelligence from './pages/CustomerIntelligence';
import LookalikeBuilder from './pages/LookalikeBuilder';
import ModelRegistry from './pages/ModelRegistry';
import AgentChat from './components/AgentChat';

export default function App() {
  const [chatOpen, setChatOpen] = useState(false);

  return (
    <BrowserRouter>
      <div style={{ display: 'flex', height: '100vh' }}>
        {/* Sidebar nav */}
        <nav style={{
          width: 230, background: 'linear-gradient(180deg, #0f172a 0%, #1e293b 100%)',
          padding: '24px 0', flexShrink: 0, display: 'flex', flexDirection: 'column',
        }}>
          <div style={{ padding: '0 20px', marginBottom: 32 }}>
            <div style={{ fontSize: 11, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 1.2, color: '#64748b', marginBottom: 6 }}>
              Summit Brands
            </div>
            <div style={{ fontSize: 15, fontWeight: 600, color: '#f1f5f9', lineHeight: 1.3 }}>
              Marketing<br />Command Center
            </div>
          </div>

          <div style={{ flex: 1 }}>
            <NavItem to="/" icon="chart">Forecast Dashboard</NavItem>
            <NavItem to="/customers" icon="users">Customer Intelligence</NavItem>
            <NavItem to="/lookalike" icon="target">Lookalike Builder</NavItem>
            <NavItem to="/agent" icon="message">Agent Chat</NavItem>
          </div>

          <div style={{ padding: '0 8px', marginBottom: 8 }}>
            <NavItem to="/models" icon="box">Model Registry</NavItem>
          </div>
        </nav>

        {/* Main content */}
        <main style={{ flex: 1, overflow: 'auto', padding: '24px 32px', background: '#f5f7fa', minWidth: 0 }}>
          <Routes>
            <Route path="/" element={<ForecastDashboard />} />
            <Route path="/customers" element={<CustomerIntelligence />} />
            <Route path="/lookalike" element={<LookalikeBuilder />} />
            <Route path="/models" element={<ModelRegistry />} />
            <Route path="/agent" element={<AgentFullPage />} />
          </Routes>
        </main>

        {/* Floating agent FAB */}
        <button
          onClick={() => setChatOpen(!chatOpen)}
          style={{
            position: 'fixed', bottom: 24, right: 24, width: 52, height: 52,
            borderRadius: '50%', border: 'none', cursor: 'pointer',
            background: chatOpen ? '#1e293b' : '#2563eb',
            color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center',
            boxShadow: '0 4px 12px rgba(0,0,0,0.2)', zIndex: 1000,
            transition: 'background 0.2s, transform 0.2s',
          }}
          onMouseEnter={e => (e.currentTarget.style.transform = 'scale(1.08)')}
          onMouseLeave={e => (e.currentTarget.style.transform = 'scale(1)')}
        >
          {chatOpen ? (
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
          ) : (
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
          )}
        </button>

        {/* Floating chat popover */}
        {chatOpen && (
          <div style={{
            position: 'fixed', bottom: 88, right: 24, width: 420, height: 560,
            borderRadius: 16, overflow: 'hidden', background: '#fff', zIndex: 999,
            boxShadow: '0 8px 30px rgba(0,0,0,0.18), 0 0 0 1px rgba(0,0,0,0.05)',
            display: 'flex', flexDirection: 'column',
            animation: 'fadeInUp 0.2s ease-out',
          }}>
            <AgentChat />
          </div>
        )}
      </div>
    </BrowserRouter>
  );
}

function AgentFullPage() {
  const [threads, setThreads] = useState<{ id: number; title: string; active: boolean }[]>([]);
  const [activeThread, setActiveThread] = useState(0);
  const [triggerMsg, setTriggerMsg] = useState<string | undefined>();

  const suggestions = [
    'What are the top-selling brands at Walmart this week?',
    'Compare forecast accuracy across all retailers',
    'Which customer segments have the highest LTV?',
    'Show me POS sales trends for Peak Hydro over the last 12 weeks',
    'Week-over-week growth of all brands at Target',
    'What is the average repurchase score by segment?',
  ];

  function startNew(msg?: string) {
    const id = Date.now();
    setThreads(prev => prev.map(t => ({ ...t, active: false })).concat({ id, title: msg || 'New chat', active: true }));
    setActiveThread(id);
    setTriggerMsg(msg);
  }

  function selectThread(id: number) {
    setActiveThread(id);
    setThreads(prev => prev.map(t => ({ ...t, active: t.id === id })));
    setTriggerMsg(undefined);
  }

  function handleFirstMessage(text: string) {
    setThreads(prev => prev.map(t => t.id === activeThread ? { ...t, title: text.substring(0, 50) } : t));
  }

  return (
    <div style={{ maxWidth: 1280, margin: '0 auto', height: 'calc(100vh - 48px)', display: 'flex', flexDirection: 'column' }}>
      <div style={{ marginBottom: 16 }}>
        <h1 style={{ fontSize: 22, marginBottom: 4 }}>Agent Chat</h1>
        <p style={{ fontSize: 13, color: '#6b7280', margin: 0 }}>
          Ask questions about demand forecasts, customer segments, POS sell-through, and marketing analytics.
        </p>
      </div>

      <div style={{ display: 'flex', gap: 16, flex: 1, minHeight: 0 }}>
        {/* Threads sidebar */}
        <div style={{ width: 240, flexShrink: 0, display: 'flex', flexDirection: 'column' }}>
          <button onClick={() => startNew()} style={{
            width: '100%', padding: '8px 12px', marginBottom: 8, borderRadius: 6, border: '1px solid #d1d5db',
            background: '#fff', fontSize: 12, cursor: 'pointer', fontWeight: 500, color: '#374151',
          }}>
            + New Chat
          </button>
          <div style={{ flex: 1, overflow: 'auto' }}>
            {threads.slice().reverse().map(t => (
              <div key={t.id} onClick={() => selectThread(t.id)} style={{
                padding: '8px 10px', marginBottom: 2, borderRadius: 6, fontSize: 12, cursor: 'pointer',
                background: t.active ? '#eff6ff' : 'transparent',
                color: t.active ? '#1d4ed8' : '#6b7280',
                fontWeight: t.active ? 500 : 400,
                overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
              }}>
                {t.title}
              </div>
            ))}
            {threads.length === 0 && (
              <p style={{ fontSize: 11, color: '#9ca3af', textAlign: 'center', marginTop: 20 }}>
                No conversations yet
              </p>
            )}
          </div>
        </div>

        {/* Main chat */}
        <div style={{
          flex: 1, background: '#fff', borderRadius: 12,
          boxShadow: '0 1px 3px rgba(0,0,0,0.08), 0 0 0 1px rgba(0,0,0,0.03)',
          overflow: 'hidden', display: 'flex', flexDirection: 'column', minWidth: 0,
        }}>
          {activeThread ? (
            <AgentChat key={activeThread} initialMessage={triggerMsg} onFirstMessage={handleFirstMessage} />
          ) : (
            <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#9ca3af', fontSize: 14 }}>
              Start a new chat or select a conversation
            </div>
          )}
        </div>

        {/* Suggestions sidebar */}
        <div style={{ width: 220, flexShrink: 0 }}>
          <div style={{
            background: '#fff', borderRadius: 12, padding: 16,
            boxShadow: '0 1px 3px rgba(0,0,0,0.08), 0 0 0 1px rgba(0,0,0,0.03)',
          }}>
            <div style={{ fontSize: 12, fontWeight: 600, color: '#374151', marginBottom: 10 }}>Try asking</div>
            {suggestions.map((s, i) => (
              <div key={i} onClick={() => startNew(s)} style={{
                padding: '8px 10px', marginBottom: 6, borderRadius: 6, fontSize: 12, color: '#374151',
                background: '#f9fafb', border: '1px solid #f3f4f6', cursor: 'pointer', lineHeight: 1.4,
                transition: 'background 0.1s',
              }}
              onMouseEnter={e => (e.currentTarget.style.background = '#eff6ff')}
              onMouseLeave={e => (e.currentTarget.style.background = '#f9fafb')}
              >
                {s}
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

const svgIcons: Record<string, React.ReactNode> = {
  chart: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/></svg>,
  users: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>,
  target: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="6"/><circle cx="12" cy="12" r="2"/></svg>,
  box: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><polyline points="3.27 6.96 12 12.01 20.73 6.96"/><line x1="12" y1="22.08" x2="12" y2="12"/></svg>,
  message: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>,
};

function NavItem({ to, icon, children }: { to: string; icon: string; children: React.ReactNode }) {
  return (
    <NavLink
      to={to}
      style={({ isActive }) => ({
        display: 'flex', alignItems: 'center', gap: 10,
        padding: '10px 20px', margin: '2px 8px', borderRadius: 6,
        color: isActive ? '#fff' : '#94a3b8',
        background: isActive ? 'rgba(59,130,246,0.15)' : 'transparent',
        textDecoration: 'none', fontSize: 13, fontWeight: isActive ? 500 : 400,
        transition: 'all 0.15s',
      })}
    >
      <span style={{ width: 20, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{svgIcons[icon]}</span>
      {children}
    </NavLink>
  );
}
