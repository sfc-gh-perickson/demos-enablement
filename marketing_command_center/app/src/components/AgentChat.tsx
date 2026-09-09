import { useState, useRef, useEffect } from 'react';
import Markdown from 'react-markdown';
import { streamAgentResponse, AgentMessage, ContentBlock } from '../api/agent';

interface DisplayMessage {
  role: 'user' | 'assistant';
  content: string;
  blocks?: ContentBlock[];
}

interface AgentChatProps {
  initialMessage?: string;
  onFirstMessage?: (text: string) => void;
}

export default function AgentChat({ initialMessage, onFirstMessage }: AgentChatProps) {
  const [messages, setMessages] = useState<DisplayMessage[]>([]);
  const [input, setInput] = useState('');
  const [streaming, setStreaming] = useState(false);
  const [statusText, setStatusText] = useState('');
  const bottomRef = useRef<HTMLDivElement>(null);
  const initialSent = useRef(false);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, statusText]);

  useEffect(() => {
    if (initialMessage && !initialSent.current) {
      initialSent.current = true;
      sendMessage(initialMessage);
    }
  }, [initialMessage]);

  async function sendMessage(text: string) {
    if (!text.trim() || streaming) return;

    const userMsg: DisplayMessage = { role: 'user', content: text.trim() };
    const newMessages = [...messages, userMsg];
    setMessages(newMessages);
    setInput('');
    setStreaming(true);
    setStatusText('Planning...');
    if (onFirstMessage && newMessages.length === 1) onFirstMessage(text.trim());

    try {
      const agentMessages: AgentMessage[] = newMessages.map(m => ({ role: m.role, content: m.content }));
      const result = await streamAgentResponse(agentMessages, setStatusText);
      const textContent = result.blocks.filter(b => b.type === 'text').map(b => (b as { type: 'text'; text: string }).text).join('\n\n');

      setMessages([...newMessages, {
        role: 'assistant',
        content: textContent,
        blocks: result.blocks,
      }]);
    } catch (err) {
      setMessages([...newMessages, {
        role: 'assistant',
        content: `Error: ${err instanceof Error ? err.message : 'Unknown'}`,
      }]);
    } finally {
      setStreaming(false);
      setStatusText('');
    }
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div style={{ padding: '12px 16px', borderBottom: '1px solid #e5e7eb', fontWeight: 500, fontSize: 14 }}>
        Marketing Command Center Agent
      </div>

      <div style={{ flex: 1, overflow: 'auto', padding: 16 }}>
        {messages.length === 0 && (
          <p style={{ color: '#999', fontSize: 13, textAlign: 'center', marginTop: 40 }}>
            Ask about forecasts, customer segments, or sales trends.
          </p>
        )}
        {messages.map((msg, i) => (
          <div key={i} style={{ marginBottom: 12, textAlign: msg.role === 'user' ? 'right' : 'left' }}>
            {msg.role === 'user' ? (
              <div style={{
                display: 'inline-block', maxWidth: '85%', padding: '8px 12px', borderRadius: 12,
                background: '#2563eb', color: '#fff', fontSize: 13, lineHeight: 1.5,
              }}>
                {msg.content}
              </div>
            ) : (
              <div style={{ maxWidth: '95%', textAlign: 'left' }}>
                {msg.blocks ? (
                  <BlockRenderer blocks={msg.blocks} />
                ) : (
                  <div style={{ ...bubbleStyle }}>
                    <div className="agent-markdown"><Markdown>{msg.content}</Markdown></div>
                  </div>
                )}
              </div>
            )}
          </div>
        ))}
        {streaming && (
          <div style={{ marginBottom: 12 }}>
            <div style={{ ...bubbleStyle, color: '#6b7280' }}>
              {statusText || 'Thinking...'}
              <span style={{ marginLeft: 4 }}>...</span>
            </div>
          </div>
        )}
        <div ref={bottomRef} />
      </div>

      <div style={{ padding: 12, borderTop: '1px solid #e5e7eb', display: 'flex', gap: 8 }}>
        <input
          value={input}
          onChange={e => setInput(e.target.value)}
          onKeyDown={e => e.key === 'Enter' && sendMessage(input)}
          placeholder="Ask a question..."
          style={{ flex: 1, padding: '8px 12px', border: '1px solid #ddd', borderRadius: 8, fontSize: 13 }}
        />
        <button
          onClick={() => sendMessage(input)}
          disabled={streaming || !input.trim()}
          style={{
            padding: '8px 16px', background: '#2563eb', color: '#fff',
            border: 'none', borderRadius: 8, cursor: 'pointer', fontSize: 13,
          }}
        >
          Send
        </button>
      </div>
    </div>
  );
}

const bubbleStyle: React.CSSProperties = {
  display: 'inline-block', maxWidth: '100%', padding: '10px 14px', borderRadius: 12,
  background: '#f3f4f6', color: '#1f2937', fontSize: 13, lineHeight: 1.6,
};

function BlockRenderer({ blocks }: { blocks: ContentBlock[] }) {
  const thinking = blocks.filter(b => b.type === 'thinking').map(b => (b as { type: 'thinking'; text: string }).text).join('\n\n');
  const visible = blocks.filter(b => b.type !== 'thinking');

  return (
    <>
      {visible.map((block, i) => {
        switch (block.type) {
          case 'text':
            return (
              <div key={i} style={{ ...bubbleStyle, marginBottom: 8 }}>
                <div className="agent-markdown"><Markdown>{block.text}</Markdown></div>
                {thinking && i === visible.length - 1 && (
                  <details style={{ marginTop: 8, borderTop: '1px solid #e5e7eb', paddingTop: 8 }}>
                    <summary style={{ cursor: 'pointer', fontSize: 11, color: '#6b7280', userSelect: 'none' }}>
                      Show reasoning
                    </summary>
                    <div style={{ fontSize: 12, color: '#6b7280', marginTop: 6, whiteSpace: 'pre-wrap' }}>{thinking}</div>
                  </details>
                )}
              </div>
            );
          case 'table':
            return <AgentTable key={i} title={block.title} columns={block.columns} rows={block.rows} />;
          case 'chart':
            return <AgentChart key={i} spec={block.spec} />;
          default:
            return null;
        }
      })}
    </>
  );
}

function AgentTable({ title, columns, rows }: { title: string; columns: string[]; rows: string[][] }) {
  return (
    <div style={{ marginBottom: 8, borderRadius: 8, border: '1px solid #e5e7eb', overflow: 'hidden', background: '#fff' }}>
      {title && <div style={{ padding: '8px 12px', fontSize: 12, fontWeight: 600, color: '#374151', borderBottom: '1px solid #e5e7eb', background: '#f9fafb' }}>{title}</div>}
      <div style={{ overflowX: 'auto' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 12 }}>
          <thead>
            <tr>
              {columns.map((col, i) => (
                <th key={i} style={{ padding: '6px 10px', textAlign: 'left', fontWeight: 600, color: '#374151', borderBottom: '2px solid #e5e7eb', background: '#f9fafb', whiteSpace: 'nowrap' }}>
                  {col}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row, ri) => (
              <tr key={ri} style={{ borderBottom: '1px solid #f3f4f6' }}>
                {row.map((cell, ci) => (
                  <td key={ci} style={{ padding: '5px 10px', whiteSpace: 'nowrap', color: '#1f2937' }}>
                    {formatCell(cell, columns[ci])}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function formatCell(val: string, _col: string): string {
  if (val === null || val === undefined) return '-';
  const num = Number(val);
  if (!isNaN(num) && val.trim() !== '') {
    if (Math.abs(num) >= 1000) return num.toLocaleString(undefined, { maximumFractionDigits: 2 });
    if (val.includes('.')) return num.toFixed(2);
  }
  return val;
}

function AgentChart({ spec }: { spec: string }) {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let cancelled = false;
    async function render() {
      if (!containerRef.current) return;
      try {
        const vegaEmbed = (await import('vega-embed')).default;
        const parsed = JSON.parse(spec);
        // Make chart responsive to container width
        parsed.width = 'container';
        if (!parsed.height) parsed.height = 240;
        parsed.autosize = { type: 'fit', contains: 'padding' };
        // Clean up the chart styling
        parsed.config = {
          ...parsed.config,
          background: 'transparent',
          font: 'system-ui, sans-serif',
          axis: { labelFontSize: 11, titleFontSize: 12, gridColor: '#f0f0f0', domainColor: '#d1d5db', tickColor: '#d1d5db' },
          legend: { labelFontSize: 11, titleFontSize: 12 },
          view: { stroke: 'transparent' },
          range: { category: ['#2563eb', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#06b6d4'] },
        };
        if (!cancelled) {
          await vegaEmbed(containerRef.current, parsed, {
            actions: false,
            renderer: 'svg',
          });
        }
      } catch (err) {
        if (!cancelled && containerRef.current) {
          containerRef.current.textContent = `Chart error: ${err instanceof Error ? err.message : 'Unknown'}`;
        }
      }
    }
    render();
    return () => { cancelled = true; };
  }, [spec]);

  return (
    <div style={{ marginBottom: 8, borderRadius: 8, border: '1px solid #e5e7eb', overflow: 'hidden', background: '#fff', padding: '12px 12px 4px' }}>
      <div ref={containerRef} style={{ width: '100%' }} />
    </div>
  );
}
