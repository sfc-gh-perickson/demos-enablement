'use client';

import Link from 'next/link';
import { useState, useMemo } from 'react';

interface Priority {
  CUSTOMER_ID: string;
  FRAUD_PROBABILITY: number;
  PRIORITY_RANK: number;
  TOP_FACTORS: any;
  RISK_TIER: string;
  INVESTIGATION_STATUS: string;
}

type SortField = 'FRAUD_PROBABILITY' | 'RISK_TIER' | null;
type SortDir = 'asc' | 'desc';

const RISK_ORDER: Record<string, number> = { HIGH: 3, MEDIUM: 2, LOW: 1 };

export function PriorityTable({ priorities }: { priorities: Priority[] }) {
  const [sortField, setSortField] = useState<SortField>(null);
  const [sortDir, setSortDir] = useState<SortDir>('desc');
  const [filter, setFilter] = useState<'all' | 'agent_reviewed'>('all');

  const displayed = useMemo(() => {
    let items = priorities;
    if (filter === 'agent_reviewed') {
      items = items.filter((p) => p.INVESTIGATION_STATUS === 'AGENT_REVIEWED');
    }
    if (sortField) {
      items = [...items].sort((a, b) => {
        let cmp = 0;
        if (sortField === 'FRAUD_PROBABILITY') {
          cmp = a.FRAUD_PROBABILITY - b.FRAUD_PROBABILITY;
        } else {
          cmp = (RISK_ORDER[a.RISK_TIER] || 0) - (RISK_ORDER[b.RISK_TIER] || 0);
        }
        return sortDir === 'desc' ? -cmp : cmp;
      });
    }
    return items;
  }, [priorities, sortField, sortDir, filter]);

  function toggleSort(field: SortField) {
    if (sortField === field) {
      setSortDir((d) => (d === 'desc' ? 'asc' : 'desc'));
    } else {
      setSortField(field);
      setSortDir('desc');
    }
  }

  function SortIndicator({ field }: { field: SortField }) {
    if (sortField !== field) return <span className="text-sf-text-dim ml-1">↕</span>;
    return <span className="text-sf-accent ml-1">{sortDir === 'desc' ? '↓' : '↑'}</span>;
  }

  return (
    <div className="bg-sf-card rounded-lg border border-sf-border overflow-hidden">
      <div className="px-6 py-4 border-b border-sf-border flex items-center justify-between">
        <h2 className="text-lg font-semibold text-white">Fraud Priorities</h2>
        <div className="flex rounded-lg overflow-hidden border border-sf-border">
          <button
            onClick={() => setFilter('all')}
            className={`px-3 py-1.5 text-xs font-medium transition-colors ${
              filter === 'all'
                ? 'bg-sf-accent text-white'
                : 'bg-sf-card-deep text-sf-text-muted hover:text-white'
            }`}
          >
            All Alerts
          </button>
          <button
            onClick={() => setFilter('agent_reviewed')}
            className={`px-3 py-1.5 text-xs font-medium transition-colors ${
              filter === 'agent_reviewed'
                ? 'bg-sf-accent text-white'
                : 'bg-sf-card-deep text-sf-text-muted hover:text-white'
            }`}
          >
            Ready for Review
          </button>
        </div>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full">
          <thead className="bg-sf-card-deep">
            <tr>
              <th className="px-4 py-3 text-left text-xs font-medium text-sf-text-muted uppercase">Rank</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-sf-text-muted uppercase">Customer</th>
              <th
                className="px-4 py-3 text-left text-xs font-medium text-sf-text-muted uppercase cursor-pointer select-none hover:text-white"
                onClick={() => toggleSort('FRAUD_PROBABILITY')}
              >
                Probability <SortIndicator field="FRAUD_PROBABILITY" />
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-sf-text-muted uppercase">Top Factors</th>
              <th
                className="px-4 py-3 text-left text-xs font-medium text-sf-text-muted uppercase cursor-pointer select-none hover:text-white"
                onClick={() => toggleSort('RISK_TIER')}
              >
                Risk Tier <SortIndicator field="RISK_TIER" />
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-sf-text-muted uppercase">Status</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-sf-text-muted uppercase">Action</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-sf-border">
            {displayed.map((p) => {
              const factors = typeof p.TOP_FACTORS === 'string'
                ? JSON.parse(p.TOP_FACTORS)
                : p.TOP_FACTORS;

              return (
                <tr key={p.CUSTOMER_ID} className="hover:bg-sf-hover transition-colors">
                  <td className="px-4 py-3 text-sm font-mono text-sf-text-muted">#{p.PRIORITY_RANK}</td>
                  <td className="px-4 py-3 text-sm font-mono text-white">{p.CUSTOMER_ID}</td>
                  <td className="px-4 py-3">
                    <ProbabilityBar value={p.FRAUD_PROBABILITY} />
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex flex-wrap gap-1">
                      {(factors || []).slice(0, 3).map((f: any, i: number) => (
                        <span
                          key={i}
                          className={`text-xs px-2 py-0.5 rounded-full ${
                            f.direction === 'increases_risk'
                              ? 'bg-red-900/30 text-red-300'
                              : 'bg-green-900/30 text-green-300'
                          }`}
                        >
                          {f.feature.replace(/_/g, ' ').toLowerCase()}
                        </span>
                      ))}
                    </div>
                  </td>
                  <td className="px-4 py-3">
                    <RiskBadge tier={p.RISK_TIER} />
                  </td>
                  <td className="px-4 py-3">
                    <StatusBadge status={p.INVESTIGATION_STATUS} />
                  </td>
                  <td className="px-4 py-3">
                    <Link
                      href={`/investigate/${p.CUSTOMER_ID}`}
                      className="text-sf-accent hover:text-sf-accent-hover text-sm font-medium"
                    >
                      {p.INVESTIGATION_STATUS === 'PENDING' ? 'View Dashboard →' : 'View Report →'}
                    </Link>
                  </td>
                </tr>
              );
            })}
            {displayed.length === 0 && (
              <tr>
                <td colSpan={7} className="px-4 py-8 text-center text-sf-text-dim">
                  No alerts match the current filter.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function ProbabilityBar({ value }: { value: number }) {
  const pct = Math.round(value * 100);
  const color = pct > 95 ? 'bg-red-500' : pct > 80 ? 'bg-yellow-500' : 'bg-sf-accent';
  return (
    <div className="flex items-center gap-2">
      <div className="w-20 h-2 bg-sf-border rounded-full overflow-hidden">
        <div className={`h-full ${color} rounded-full`} style={{ width: `${pct}%` }} />
      </div>
      <span className="text-xs text-sf-text-muted font-mono">{pct}%</span>
    </div>
  );
}

function RiskBadge({ tier }: { tier: string }) {
  const colors: Record<string, string> = {
    HIGH: 'bg-red-900/30 text-red-300 border-red-800',
    MEDIUM: 'bg-yellow-900/30 text-yellow-300 border-yellow-800',
    LOW: 'bg-green-900/30 text-green-300 border-green-800',
  };
  return (
    <span className={`text-xs px-2 py-0.5 rounded border ${colors[tier] || colors.LOW}`}>
      {tier}
    </span>
  );
}

function StatusBadge({ status }: { status: string }) {
  const colors: Record<string, string> = {
    PENDING: 'bg-sf-card-deep text-sf-text-muted',
    AGENT_REVIEWED: 'bg-sf-accent-muted text-sf-accent',
    ESCALATED: 'bg-red-900/30 text-red-300',
    MONITORING: 'bg-yellow-900/30 text-yellow-300',
    CLEARED: 'bg-green-900/30 text-green-300',
  };
  const labels: Record<string, string> = {
    PENDING: 'Pending',
    AGENT_REVIEWED: 'Needs Review',
    ESCALATED: 'Escalated',
    MONITORING: 'Monitoring',
    CLEARED: 'Cleared',
  };
  return (
    <span className={`text-xs px-2 py-1 rounded ${colors[status] || colors.PENDING}`}>
      {labels[status] || status}
    </span>
  );
}
