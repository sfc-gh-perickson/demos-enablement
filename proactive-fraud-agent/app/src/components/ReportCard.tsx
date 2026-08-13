'use client';

import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';

interface ReportProps {
  report: string;
  action: string;
  investigatedAt: string;
}

export function ReportCard({ report, action, investigatedAt }: ReportProps) {
  const actionColors: Record<string, string> = {
    ESCALATE: 'bg-red-900/30 text-red-300 border-red-700',
    MONITOR: 'bg-yellow-900/30 text-yellow-300 border-yellow-700',
    BLOCK: 'bg-orange-900/30 text-orange-300 border-orange-700',
    CLEAR: 'bg-green-900/30 text-green-300 border-green-700',
  };

  return (
    <div className="bg-sf-card rounded-lg border border-sf-border p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-semibold text-sf-text-muted">Investigation Report</h3>
        <div className="flex items-center gap-3">
          <span className={`text-xs px-3 py-1 rounded border ${actionColors[action] || actionColors.MONITOR}`}>
            {action}
          </span>
          {investigatedAt && (
            <span className="text-xs text-sf-text-dim">
              {new Date(investigatedAt).toLocaleString()}
            </span>
          )}
        </div>
      </div>
      <div className="prose prose-invert prose-sm max-w-none text-sf-text-muted [&_h1]:text-lg [&_h2]:text-base [&_h3]:text-sm [&_h1]:text-white [&_h2]:text-sf-text [&_h3]:text-sf-text-muted [&_p]:mb-3 [&_ul]:mb-3 [&_li]:text-sf-text-muted [&_strong]:text-white [&_code]:text-sf-accent [&_code]:bg-sf-accent-muted [&_code]:px-1 [&_code]:rounded [&_table]:w-full [&_table]:text-xs [&_th]:px-2 [&_th]:py-1 [&_th]:text-left [&_th]:border-b [&_th]:border-sf-border [&_th]:text-sf-text-muted [&_td]:px-2 [&_td]:py-1 [&_td]:border-b [&_td]:border-sf-border/50 [&_td]:text-sf-text-muted">
        <ReactMarkdown remarkPlugins={[remarkGfm]}>{report}</ReactMarkdown>
      </div>
    </div>
  );
}
