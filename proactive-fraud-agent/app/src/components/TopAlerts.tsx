'use client';

import { useState } from 'react';
import Link from 'next/link';

interface Alert {
  CUSTOMER_ID: string;
  FRAUD_PROBABILITY: number;
  PRIORITY_RANK: number;
  RISK_TIER: string;
  RECOMMENDED_ACTION: string;
  TOP_FACTORS: any;
  CREDIT_LIMIT?: number;
  RECENT_TXN_VOLUME?: number;
  EXPECTED_LOSS?: number;
}

interface TopAlertsProps {
  alertsByProbability: Alert[];
  alertsByLoss: Alert[];
}

export function TopAlerts({ alertsByProbability, alertsByLoss }: TopAlertsProps) {
  const [mode, setMode] = useState<'probability' | 'loss'>('probability');
  const alerts = mode === 'probability' ? alertsByProbability : alertsByLoss;

  return (
    <div className="bg-sf-card rounded-lg border border-sf-border overflow-hidden">
      <div className="px-6 py-4 border-b border-sf-border flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold text-white">Most Pressing Cases</h2>
          <p className="text-xs text-sf-text-dim mt-1">
            {mode === 'probability'
              ? 'Ranked by fraud probability'
              : 'Ranked by expected loss (probability x credit limit + transaction volume)'}
          </p>
        </div>
        <div className="flex rounded-lg overflow-hidden border border-sf-border">
          <button
            onClick={() => setMode('probability')}
            className={`px-3 py-1.5 text-xs font-medium transition-colors ${
              mode === 'probability'
                ? 'bg-sf-accent text-white'
                : 'bg-sf-card-deep text-sf-text-muted hover:text-white'
            }`}
          >
            By Probability
          </button>
          <button
            onClick={() => setMode('loss')}
            className={`px-3 py-1.5 text-xs font-medium transition-colors ${
              mode === 'loss'
                ? 'bg-sf-accent text-white'
                : 'bg-sf-card-deep text-sf-text-muted hover:text-white'
            }`}
          >
            Loss-Weighted
          </button>
        </div>
      </div>
      <div className="divide-y divide-sf-border">
        {alerts.map((a, i) => {
          const factors = typeof a.TOP_FACTORS === 'string'
            ? JSON.parse(a.TOP_FACTORS)
            : a.TOP_FACTORS;
          const topFactorNames = (factors || [])
            .slice(0, 3)
            .filter((f: any) => f.direction === 'increases_risk')
            .map((f: any) => f.feature.replace(/_/g, ' ').toLowerCase());

          const pct = Math.round(a.FRAUD_PROBABILITY * 100);
          const narrative = buildNarrative(pct, a.RECOMMENDED_ACTION, topFactorNames, mode, a);

          return (
            <Link
              key={a.CUSTOMER_ID}
              href={`/investigate/${a.CUSTOMER_ID}`}
              className="flex items-start gap-4 px-6 py-4 hover:bg-sf-hover transition-colors group"
            >
              <div className="flex-shrink-0 w-8 h-8 rounded-full bg-red-900/30 border border-red-800 flex items-center justify-center">
                <span className="text-sm font-bold text-red-400">{i + 1}</span>
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-3 mb-1">
                  <span className="text-sm font-mono font-medium text-white">{a.CUSTOMER_ID}</span>
                  <span className="text-xs font-mono text-red-400">{pct}% risk</span>
                  {mode === 'loss' && a.EXPECTED_LOSS != null && (
                    <span className="text-xs font-mono text-yellow-400">
                      ${Math.round(a.EXPECTED_LOSS).toLocaleString()} exp. loss
                    </span>
                  )}
                  <ActionBadge action={a.RECOMMENDED_ACTION} />
                </div>
                <p className="text-sm text-sf-text-muted leading-relaxed">{narrative}</p>
              </div>
              <span className="text-sf-text-dim group-hover:text-sf-accent transition-colors text-sm mt-1">
                Review →
              </span>
            </Link>
          );
        })}
      </div>
    </div>
  );
}

function buildNarrative(
  pct: number,
  action: string,
  factors: string[],
  mode: 'probability' | 'loss',
  alert: Alert,
): string {
  const factorStr = factors.length > 0
    ? `Key risk signals: ${factors.join(', ')}.`
    : '';

  const actionStr: Record<string, string> = {
    ESCALATE: 'Agent recommends immediate escalation.',
    BLOCK: 'Agent recommends blocking the account.',
    MONITOR: 'Agent recommends enhanced monitoring.',
    CLEAR: 'Agent found low risk after analysis.',
  };

  let lossContext = '';
  if (mode === 'loss') {
    const parts: string[] = [];
    if (alert.CREDIT_LIMIT) {
      parts.push(`$${alert.CREDIT_LIMIT.toLocaleString()} credit limit`);
    }
    if (alert.RECENT_TXN_VOLUME) {
      parts.push(`$${Math.round(alert.RECENT_TXN_VOLUME).toLocaleString()} in recent transactions`);
    }
    if (parts.length > 0) {
      lossContext = `Exposure: ${parts.join(', ')}. `;
    }
  }

  return `${pct}% fraud probability. ${lossContext}${factorStr} ${actionStr[action] || `Recommended: ${action}.`}`.trim();
}

function ActionBadge({ action }: { action: string }) {
  const colors: Record<string, string> = {
    ESCALATE: 'bg-red-900/40 text-red-300 border-red-800',
    BLOCK: 'bg-orange-900/40 text-orange-300 border-orange-800',
    MONITOR: 'bg-yellow-900/40 text-yellow-300 border-yellow-800',
    CLEAR: 'bg-green-900/40 text-green-300 border-green-800',
  };

  return (
    <span className={`text-[10px] px-1.5 py-0.5 rounded border ${colors[action] || 'bg-sf-card-deep text-sf-text-muted border-sf-border'}`}>
      {action}
    </span>
  );
}
