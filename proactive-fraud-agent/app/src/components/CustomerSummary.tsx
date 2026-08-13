'use client';

interface CustomerSummaryProps {
  investigation: {
    CUSTOMER_ID: string;
    FRAUD_PROBABILITY: number;
    PRIORITY_RANK: number;
    RISK_TIER?: string;
    INVESTIGATED_AT?: string;
    RECOMMENDED_ACTION?: string;
    INVESTIGATION_STATUS?: string;
    FIRST_NAME?: string;
    LAST_NAME?: string;
    EMAIL?: string;
    PHONE?: string;
    ADDRESS_CITY?: string;
    ADDRESS_STATE?: string;
    ACCOUNT_OPEN_DATE?: string;
    ACCOUNT_STATUS?: string;
    CREDIT_LIMIT?: number;
  };
}

export function CustomerSummary({ investigation }: CustomerSummaryProps) {
  const prob = investigation.FRAUD_PROBABILITY;
  const pct = (prob * 100).toFixed(1);

  const probColor =
    prob >= 0.8 ? 'text-red-400' : prob >= 0.5 ? 'text-orange-400' : 'text-yellow-400';

  const riskTierColors: Record<string, string> = {
    CRITICAL: 'bg-red-900/40 text-red-300 border-red-700',
    HIGH: 'bg-orange-900/40 text-orange-300 border-orange-700',
    MEDIUM: 'bg-yellow-900/40 text-yellow-300 border-yellow-700',
    LOW: 'bg-green-900/40 text-green-300 border-green-700',
  };

  const actionColors: Record<string, string> = {
    ESCALATE: 'bg-red-900/30 text-red-300 border-red-700',
    MONITOR: 'bg-yellow-900/30 text-yellow-300 border-yellow-700',
    BLOCK: 'bg-orange-900/30 text-orange-300 border-orange-700',
    CLEAR: 'bg-green-900/30 text-green-300 border-green-700',
    PENDING: 'bg-sf-card-deep text-sf-text-muted border-sf-border',
  };

  const riskTier = investigation.RISK_TIER || 'MEDIUM';
  const action = investigation.RECOMMENDED_ACTION || 'PENDING';
  const fullName =
    investigation.FIRST_NAME && investigation.LAST_NAME
      ? `${investigation.FIRST_NAME} ${investigation.LAST_NAME}`
      : null;

  return (
    <div className="bg-sf-card rounded-lg border border-sf-border p-5">
      {/* Fraud score hero */}
      <div className="text-center mb-5 pb-5 border-b border-sf-border">
        <div className={`text-4xl font-bold ${probColor}`}>{pct}%</div>
        <div className="text-xs text-sf-text-dim mt-1">Fraud Probability</div>
        <div className="flex items-center justify-center gap-2 mt-3">
          <span className={`text-xs px-2.5 py-0.5 rounded border ${riskTierColors[riskTier]}`}>
            {riskTier}
          </span>
          <span className={`text-xs px-2.5 py-0.5 rounded border ${actionColors[action]}`}>
            {action}
          </span>
        </div>
      </div>

      {/* Customer details */}
      <div className="space-y-3 text-sm">
        <DetailRow label="Customer" value={investigation.CUSTOMER_ID} />
        {fullName && <DetailRow label="Name" value={fullName} />}
        {investigation.EMAIL && <DetailRow label="Email" value={investigation.EMAIL} />}
        {investigation.PHONE && <DetailRow label="Phone" value={investigation.PHONE} />}
        {investigation.ADDRESS_CITY && (
          <DetailRow
            label="Location"
            value={`${investigation.ADDRESS_CITY}, ${investigation.ADDRESS_STATE || ''}`}
          />
        )}
        {investigation.ACCOUNT_OPEN_DATE && (
          <DetailRow label="Account Opened" value={investigation.ACCOUNT_OPEN_DATE} />
        )}
        {investigation.CREDIT_LIMIT != null && (
          <DetailRow label="Credit Limit" value={`$${investigation.CREDIT_LIMIT.toLocaleString()}`} />
        )}
        {investigation.ACCOUNT_STATUS && (
          <DetailRow label="Account Status" value={investigation.ACCOUNT_STATUS} />
        )}
      </div>

      {/* Meta row */}
      <div className="mt-5 pt-4 border-t border-sf-border flex items-center justify-between text-xs text-sf-text-dim">
        <span>Rank #{investigation.PRIORITY_RANK}</span>
        {investigation.INVESTIGATED_AT && (
          <span>{new Date(investigation.INVESTIGATED_AT).toLocaleDateString()}</span>
        )}
      </div>
    </div>
  );
}

function DetailRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between items-baseline">
      <span className="text-sf-text-dim">{label}</span>
      <span className="text-sf-text text-right max-w-[60%] truncate">{value}</span>
    </div>
  );
}
