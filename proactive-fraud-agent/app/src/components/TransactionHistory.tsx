interface Transaction {
  TRANSACTION_ID: string;
  TRANSACTION_AMOUNT: number;
  TRANSACTION_TIMESTAMP: string;
  CHANNEL: string;
  TRANSACTION_TYPE: string;
  MERCHANT_ID: string;
  IS_INTERNATIONAL: boolean;
  DEVICE_TYPE: string;
}

export function TransactionHistory({ transactions }: { transactions: Transaction[] }) {
  return (
    <div className="bg-sf-card rounded-lg border border-sf-border overflow-hidden">
      <div className="px-5 py-3 border-b border-sf-border">
        <h3 className="text-sm font-semibold text-sf-text-muted">Recent Transactions</h3>
      </div>
      <div className="overflow-x-auto max-h-[320px] overflow-y-auto">
        <table className="w-full">
          <thead className="bg-sf-card-deep sticky top-0">
            <tr>
              <th className="px-3 py-2 text-left text-[10px] font-medium text-sf-text-dim uppercase">Date</th>
              <th className="px-3 py-2 text-left text-[10px] font-medium text-sf-text-dim uppercase">Amount</th>
              <th className="px-3 py-2 text-left text-[10px] font-medium text-sf-text-dim uppercase">Type</th>
              <th className="px-3 py-2 text-left text-[10px] font-medium text-sf-text-dim uppercase">Channel</th>
              <th className="px-3 py-2 text-left text-[10px] font-medium text-sf-text-dim uppercase">Merchant</th>
              <th className="px-3 py-2 text-left text-[10px] font-medium text-sf-text-dim uppercase">Intl</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-sf-border">
            {transactions.map((t) => (
              <tr key={t.TRANSACTION_ID} className="hover:bg-sf-hover transition-colors">
                <td className="px-3 py-2 text-xs text-sf-text-muted font-mono whitespace-nowrap">
                  {new Date(t.TRANSACTION_TIMESTAMP).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
                </td>
                <td className="px-3 py-2 text-xs text-white font-mono">
                  ${t.TRANSACTION_AMOUNT.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                </td>
                <td className="px-3 py-2">
                  <span className="text-[10px] px-1.5 py-0.5 rounded bg-sf-hover text-sf-text-muted">
                    {t.TRANSACTION_TYPE}
                  </span>
                </td>
                <td className="px-3 py-2 text-xs text-sf-text-muted">{t.CHANNEL}</td>
                <td className="px-3 py-2 text-xs text-sf-text-muted font-mono">{t.MERCHANT_ID}</td>
                <td className="px-3 py-2 text-xs">
                  {t.IS_INTERNATIONAL ? (
                    <span className="text-yellow-400">Yes</span>
                  ) : (
                    <span className="text-sf-text-dim">No</span>
                  )}
                </td>
              </tr>
            ))}
            {transactions.length === 0 && (
              <tr>
                <td colSpan={6} className="px-3 py-6 text-center text-sf-text-dim text-sm">
                  No transactions found.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
