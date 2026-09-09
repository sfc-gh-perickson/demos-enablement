export interface AgentMessage {
  role: 'user' | 'assistant';
  content: string;
}

export type ContentBlock =
  | { type: 'text'; text: string }
  | { type: 'table'; title: string; columns: string[]; rows: string[][] }
  | { type: 'chart'; spec: string }
  | { type: 'thinking'; text: string };

export interface StreamResult {
  blocks: ContentBlock[];
}

export async function streamAgentResponse(
  messages: AgentMessage[],
  onStatus: (status: string) => void
): Promise<StreamResult> {
  const response = await fetch('/api/v2/databases/SB_COMMAND_CENTER/schemas/AGENTS/agents/MARKETING_COMMAND_CENTER:run', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      messages: messages.map(m => ({ role: m.role, content: [{ type: 'text', text: m.content }] })),
      stream: true,
    }),
  });

  if (!response.ok) {
    const err = await response.text();
    throw new Error(`Agent error ${response.status}: ${err.substring(0, 200)}`);
  }

  const reader = response.body?.getReader();
  if (!reader) return { blocks: [] };

  const decoder = new TextDecoder();
  let buffer = '';

  // Track content by content_index: { type, data }
  const contentMap = new Map<number, { kind: 'text' | 'table' | 'chart'; data: unknown }>();

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop() || '';

    let currentEvent = '';
    for (const line of lines) {
      if (line.startsWith('event: ')) {
        currentEvent = line.slice(7).trim();
      } else if (line.startsWith('data: ')) {
        const data = line.slice(6);
        if (data === '[DONE]') break;
        try {
          const parsed = JSON.parse(data);
          const idx = parsed.content_index;

          if (currentEvent === 'response.text.delta') {
            const existing = contentMap.get(idx);
            if (existing && existing.kind === 'text') {
              existing.data = (existing.data as string) + (parsed.text || '');
            } else {
              contentMap.set(idx, { kind: 'text', data: parsed.text || '' });
            }
          } else if (currentEvent === 'response.table') {
            const rs = parsed.result_set;
            if (rs) {
              contentMap.set(idx, {
                kind: 'table',
                data: {
                  title: parsed.title || '',
                  columns: rs.resultSetMetaData?.rowType?.map((c: { name: string }) => c.name) || [],
                  rows: rs.data || [],
                },
              });
            }
          } else if (currentEvent === 'response.chart') {
            if (parsed.chart_spec) {
              contentMap.set(idx, { kind: 'chart', data: parsed.chart_spec });
            }
          } else if (currentEvent === 'response.status' && parsed.message) {
            onStatus(parsed.message);
          }
        } catch {}
        currentEvent = '';
      }
    }
  }

  // Build ordered content blocks
  // Short text blocks that appear before any non-text content are planning/thinking.
  // Everything after the first non-text block (or long text) is the answer.
  const entries = [...contentMap.entries()].sort((a, b) => a[0] - b[0]);
  const blocks: ContentBlock[] = [];
  let seenSubstantive = false;

  for (const [, { kind, data }] of entries) {
    if (kind === 'text') {
      const text = data as string;
      if (!seenSubstantive && text.length < 150) {
        blocks.push({ type: 'thinking', text });
      } else {
        seenSubstantive = true;
        blocks.push({ type: 'text', text });
      }
    } else if (kind === 'table') {
      seenSubstantive = true;
      const t = data as { title: string; columns: string[]; rows: string[][] };
      blocks.push({ type: 'table', title: t.title, columns: t.columns, rows: t.rows });
    } else if (kind === 'chart') {
      seenSubstantive = true;
      blocks.push({ type: 'chart', spec: data as string });
    }
  }

  return { blocks };
}
