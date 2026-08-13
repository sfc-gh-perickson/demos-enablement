import { getInvestigation, getTransactionHistory } from '@/lib/snowflake';
import { ShapChart } from '@/components/ShapChart';
import { ReportCard } from '@/components/ReportCard';
import { ChatPanel } from '@/components/ChatPanel';
import { CustomerSummary } from '@/components/CustomerSummary';
import { RunInvestigationButton } from '@/components/RunInvestigationButton';
import { TransactionHistory } from '@/components/TransactionHistory';
import Link from 'next/link';

export const dynamic = 'force-dynamic';

interface PageProps {
  params: { customerId: string };
}

export default async function InvestigatePage({ params }: PageProps) {
  const { customerId } = params;
  let investigation: any = null;
  let transactions: any[] = [];
  let error: string | null = null;

  try {
    const [results, txns] = await Promise.all([
      getInvestigation(customerId),
      getTransactionHistory(customerId),
    ]);
    investigation = results[0] || null;
    transactions = txns;
  } catch (e: any) {
    error = e.message;
  }

  const factors = investigation?.TOP_FACTORS
    ? typeof investigation.TOP_FACTORS === 'string'
      ? JSON.parse(investigation.TOP_FACTORS)
      : investigation.TOP_FACTORS
    : [];

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center gap-4">
        <Link href="/" className="text-sf-accent hover:text-sf-accent-hover text-sm">
          &larr; Back to Dashboard
        </Link>
        <h2 className="text-xl font-semibold text-white">
          Investigation: {customerId}
        </h2>
      </div>

      {error && (
        <div className="bg-red-900/20 border border-red-800 rounded-lg p-4 text-red-300">
          Error: {error}
        </div>
      )}

      {!investigation && !error && (
        <div className="bg-sf-card rounded-lg border border-sf-border p-8 text-center text-sf-text-muted">
          No data found for customer {customerId}.
        </div>
      )}

      {investigation && (
        <div className="flex flex-col lg:flex-row gap-6">
          {/* Left panel: Customer info + SHAP + Run button + Actions */}
          <div className="w-full lg:w-[380px] lg:flex-shrink-0 space-y-5">
            <CustomerSummary investigation={investigation} />
            <ShapChart factors={factors} />
            {!investigation.INVESTIGATION_REPORT && (
              <RunInvestigationButton customerId={customerId} />
            )}
            <ActionBar customerId={customerId} />
          </div>

          {/* Right panel: Transactions on top, Report below */}
          <div className="flex-1 min-w-0 space-y-5">
            <TransactionHistory transactions={transactions} />
            {investigation.INVESTIGATION_REPORT && (
              <ReportCard
                report={investigation.INVESTIGATION_REPORT}
                action={investigation.RECOMMENDED_ACTION || 'PENDING'}
                investigatedAt={investigation.INVESTIGATED_AT || ''}
              />
            )}
          </div>
        </div>
      )}

      {/* Floating chat bubble */}
      {investigation && (
        <ChatPanel
          threadId={investigation.THREAD_ID || ''}
          parentMessageId={investigation.PARENT_MESSAGE_ID || ''}
          customerId={customerId}
          initialContext={investigation.INVESTIGATION_REPORT}
        />
      )}
    </div>
  );
}

function ActionBar({ customerId }: { customerId: string }) {
  return (
    <div className="bg-sf-card rounded-lg border border-sf-border p-4">
      <h4 className="text-xs font-semibold text-sf-text-dim uppercase tracking-wide mb-3">Actions</h4>
      <div className="flex gap-2">
        <ActionButton label="Escalate" color="red" customerId={customerId} />
        <ActionButton label="Monitor" color="yellow" customerId={customerId} />
        <ActionButton label="Clear" color="green" customerId={customerId} />
      </div>
    </div>
  );
}

function ActionButton({ label, color, customerId }: { label: string; color: string; customerId: string }) {
  const colors: Record<string, string> = {
    red: 'bg-red-600 hover:bg-red-700',
    yellow: 'bg-yellow-600 hover:bg-yellow-700',
    green: 'bg-green-600 hover:bg-green-700',
  };

  return (
    <form action={`/api/action`} method="POST" className="flex-1">
      <input type="hidden" name="customerId" value={customerId} />
      <input type="hidden" name="action" value={label.toUpperCase()} />
      <button
        type="submit"
        className={`w-full px-4 py-2 ${colors[color]} text-white text-sm font-medium rounded-lg transition-colors`}
      >
        {label}
      </button>
    </form>
  );
}
