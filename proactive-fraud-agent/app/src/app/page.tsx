import { getPriorities } from '@/lib/snowflake';
import { PriorityTable } from '@/components/PriorityTable';
import { TopAlerts } from '@/components/TopAlerts';

export const dynamic = 'force-dynamic';

export default async function Dashboard() {
  let priorities: any[] = [];
  let error: string | null = null;

  try {
    priorities = await getPriorities();
  } catch (e: any) {
    error = e.message;
  }

  const stats = {
    total: priorities.length,
    critical: priorities.filter((p) => p.FRAUD_PROBABILITY > 0.95).length,
    needsReview: priorities.filter((p) => p.INVESTIGATION_STATUS === 'AGENT_REVIEWED').length,
    pending: priorities.filter((p) => p.INVESTIGATION_STATUS === 'PENDING').length,
  };

  const top5ByProbability = priorities
    .filter((p) => p.INVESTIGATION_STATUS === 'AGENT_REVIEWED')
    .sort((a, b) => b.FRAUD_PROBABILITY - a.FRAUD_PROBABILITY)
    .slice(0, 5);

  const top5ByLoss = priorities
    .filter((p) => p.INVESTIGATION_STATUS === 'AGENT_REVIEWED')
    .sort((a, b) => {
      const lossA = (a.EXPECTED_LOSS || 0) + (a.RECENT_TXN_VOLUME || 0) * 0.01;
      const lossB = (b.EXPECTED_LOSS || 0) + (b.RECENT_TXN_VOLUME || 0) * 0.01;
      return lossB - lossA;
    })
    .slice(0, 5);

  return (
    <div className="space-y-6">
      {/* Stats Cards */}
      <div className="grid grid-cols-4 gap-4">
        <StatCard label="Total Alerts" value={stats.total} color="accent" />
        <StatCard label="Critical (>95%)" value={stats.critical} color="red" />
        <StatCard label="Needs Review" value={stats.needsReview} color="yellow" />
        <StatCard label="Pending" value={stats.pending} color="muted" />
      </div>

      {/* Top 5 Most Pressing */}
      {top5ByProbability.length > 0 && (
        <TopAlerts alertsByProbability={top5ByProbability} alertsByLoss={top5ByLoss} />
      )}

      {/* Full Queue */}
      {error ? (
        <div className="bg-red-900/20 border border-red-800 rounded-lg p-4 text-red-300">
          Error loading priorities: {error}
        </div>
      ) : (
        <PriorityTable priorities={priorities} />
      )}
    </div>
  );
}

function StatCard({ label, value, color }: { label: string; value: number; color: string }) {
  const colors: Record<string, string> = {
    accent: 'border-sf-accent text-sf-accent',
    red: 'border-red-500 text-red-400',
    yellow: 'border-yellow-500 text-yellow-400',
    muted: 'border-sf-text-dim text-sf-text-muted',
  };

  return (
    <div className={`bg-sf-card border-l-4 ${colors[color]} rounded-lg p-4`}>
      <div className="text-3xl font-bold text-white">{value}</div>
      <div className="text-sm text-sf-text-muted mt-1">{label}</div>
    </div>
  );
}
