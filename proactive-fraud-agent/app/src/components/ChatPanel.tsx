'use client';

import { useState, useRef, useEffect } from 'react';
import { createPortal } from 'react-dom';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';

interface ChatMessage {
  role: 'user' | 'assistant';
  content: string;
}

interface ChatPanelProps {
  threadId: string;
  parentMessageId: string;
  customerId: string;
  initialContext?: string;
}

export function ChatPanel({ threadId: initialThreadId, parentMessageId: initialParentMessageId, customerId, initialContext }: ChatPanelProps) {
  const [open, setOpen] = useState(false);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [currentThreadId, setCurrentThreadId] = useState(initialThreadId);
  const [currentParentMessageId, setCurrentParentMessageId] = useState(initialParentMessageId);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, loading]);

  const sendMessage = async () => {
    if (!input.trim() || loading) return;

    const userMsg = input.trim();
    setInput('');
    setMessages((prev) => [...prev, { role: 'user', content: userMsg }]);
    setLoading(true);

    try {
      const res = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ threadId: currentThreadId, parentMessageId: currentParentMessageId, customerId, message: userMsg }),
      });
      const data = await res.json();
      setMessages((prev) => [...prev, { role: 'assistant', content: data.text }]);
      if (data.threadId) {
        setCurrentThreadId(data.threadId);
      }
      if (data.parentMessageId) {
        setCurrentParentMessageId(data.parentMessageId);
      }
    } catch {
      setMessages((prev) => [...prev, { role: 'assistant', content: 'Error: Failed to get response' }]);
    } finally {
      setLoading(false);
    }
  };

  if (!mounted) return null;

  return createPortal(
    <>
      {/* Toggle tab on the right edge */}
      <button
        onClick={() => setOpen(!open)}
        className={`fixed z-[60] flex items-center gap-1.5 px-2 py-3 rounded-l-lg border border-r-0 border-sf-border bg-sf-card hover:bg-sf-hover transition-all top-1/2 -translate-y-1/2 ${
          open ? 'right-[420px]' : 'right-0'
        }`}
      >
        <svg className="w-4 h-4 text-sf-accent" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
        </svg>
        <span className="text-[10px] text-sf-text-muted font-medium [writing-mode:vertical-lr] rotate-180">
          {open ? 'Close' : 'Chat'}
        </span>
      </button>

      {/* Sidebar panel */}
      <div
        className={`fixed inset-y-0 right-0 z-[55] w-[420px] bg-sf-card border-l border-sf-border shadow-2xl flex flex-col overflow-hidden transition-transform duration-300 ${
          open ? 'translate-x-0' : 'translate-x-full'
        }`}
      >
        <div className="px-5 py-4 border-b border-sf-border flex items-center justify-between">
          <h3 className="text-sm font-semibold text-sf-text">Fraud Investigator</h3>
          {currentThreadId && (
            <span className="text-[10px] text-sf-text-dim font-mono">
              thread:{currentThreadId.slice(0, 8)}
            </span>
          )}
        </div>

        <div className="flex-1 min-h-0 overflow-y-auto p-4 space-y-4">
          {messages.length === 0 && (
            <div className="text-center mt-16 space-y-2">
              <p className="text-sm text-sf-text-muted">
                Ask questions about this customer's fraud risk
              </p>
              <p className="text-xs text-sf-text-dim">
                The agent can query transaction history, risk factors, and customer data.
              </p>
            </div>
          )}
          {messages.map((msg, i) => (
            <div
              key={i}
              className={`rounded-lg p-3 ${
                msg.role === 'user'
                  ? 'bg-sf-accent-muted border border-sf-accent/30 ml-8'
                  : 'bg-sf-card-deep border border-sf-border'
              }`}
            >
              <span className="text-[10px] text-sf-text-dim uppercase tracking-wide font-medium block mb-1.5">
                {msg.role === 'user' ? 'You' : 'Investigator'}
              </span>
              {msg.role === 'assistant' ? (
                <div className="prose prose-invert prose-sm max-w-none text-sf-text-muted [&_p]:mb-2 [&_ul]:mb-2 [&_ol]:mb-2 [&_li]:text-sf-text-muted [&_code]:text-sf-accent [&_code]:bg-sf-accent-muted [&_code]:px-1 [&_code]:rounded [&_strong]:text-white [&_table]:w-full [&_table]:text-xs [&_th]:px-2 [&_th]:py-1 [&_th]:text-left [&_th]:border-b [&_th]:border-sf-border [&_th]:text-sf-text-muted [&_td]:px-2 [&_td]:py-1 [&_td]:border-b [&_td]:border-sf-border/50 [&_td]:text-sf-text-muted">
                  <ReactMarkdown remarkPlugins={[remarkGfm]}>{msg.content}</ReactMarkdown>
                </div>
              ) : (
                <p className="text-sm text-sf-accent">{msg.content}</p>
              )}
            </div>
          ))}
          {loading && (
            <div className="bg-sf-card-deep border border-sf-border rounded-lg p-3">
              <span className="text-[10px] text-sf-text-dim uppercase tracking-wide font-medium block mb-1.5">Investigator</span>
              <div className="flex items-center gap-1.5">
                <span className="w-1.5 h-1.5 rounded-full bg-sf-accent animate-bounce [animation-delay:0ms]" />
                <span className="w-1.5 h-1.5 rounded-full bg-sf-accent animate-bounce [animation-delay:150ms]" />
                <span className="w-1.5 h-1.5 rounded-full bg-sf-accent animate-bounce [animation-delay:300ms]" />
              </div>
            </div>
          )}
          <div ref={messagesEndRef} />
        </div>

        <div className="p-3 border-t border-sf-border">
          <div className="flex gap-2">
            <input
              type="text"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && sendMessage()}
              placeholder="Ask about this case..."
              className="flex-1 bg-sf-card-deep border border-sf-border rounded-lg px-3 py-2.5 text-sm text-white placeholder-sf-text-dim focus:outline-none focus:border-sf-accent transition-colors"
            />
            <button
              onClick={sendMessage}
              disabled={loading || !input.trim()}
              className="px-4 py-2.5 bg-sf-accent hover:bg-sf-accent-hover disabled:opacity-40 disabled:cursor-not-allowed text-white text-sm font-medium rounded-lg transition-colors"
            >
              Send
            </button>
          </div>
        </div>
      </div>
    </>,
    document.body,
  );
}
