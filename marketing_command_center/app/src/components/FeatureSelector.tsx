interface FeatureSelectorProps {
  selected: string[];
  onChange: (features: string[]) => void;
}

export const AVAILABLE_FEATURES = [
  { name: 'RECENCY_DAYS', view: 'CUSTOMER_RFM_FV', desc: 'Days since last purchase' },
  { name: 'ORDER_FREQUENCY', view: 'CUSTOMER_RFM_FV', desc: 'Total number of orders' },
  { name: 'TOTAL_MONETARY', view: 'CUSTOMER_RFM_FV', desc: 'Lifetime spend' },
  { name: 'AVG_ORDER_VALUE', view: 'CUSTOMER_RFM_FV', desc: 'Average order value' },
  { name: 'BRAND_DIVERSITY', view: 'CUSTOMER_RFM_FV', desc: 'Number of distinct brands purchased' },
  { name: 'DISCOUNT_SENSITIVITY', view: 'CUSTOMER_RFM_FV', desc: 'Fraction of orders with discount' },
  { name: 'PROREWARDS_FLAG', view: 'CUSTOMER_RFM_FV', desc: 'ProRewards member indicator' },
  { name: 'AVG_BASKET_SIZE', view: 'CUSTOMER_BEHAVIOR_FV', desc: 'Average order total' },
  { name: 'AVG_BASKET_ITEMS', view: 'CUSTOMER_BEHAVIOR_FV', desc: 'Average items per order' },
  { name: 'COUPON_USAGE_RATE', view: 'CUSTOMER_BEHAVIOR_FV', desc: 'Coupon usage frequency' },
];

export default function FeatureSelector({ selected, onChange }: FeatureSelectorProps) {
  function toggleFeature(name: string) {
    if (selected.includes(name)) {
      onChange(selected.filter(f => f !== name));
    } else {
      onChange([...selected, name]);
    }
  }

  return (
    <div style={{ maxHeight: 200, overflow: 'auto' }}>
      {AVAILABLE_FEATURES.map(feat => (
        <label key={feat.name} style={{ display: 'flex', alignItems: 'center', padding: '6px 0', cursor: 'pointer', fontSize: 12 }}>
          <input
            type="checkbox"
            checked={selected.includes(feat.name)}
            onChange={() => toggleFeature(feat.name)}
            style={{ marginRight: 8 }}
          />
          <div>
            <span style={{ fontWeight: 500 }}>{feat.name}</span>
            <span style={{ color: '#999', marginLeft: 6 }}>({feat.view})</span>
            <div style={{ color: '#666', fontSize: 11 }}>{feat.desc}</div>
          </div>
        </label>
      ))}
    </div>
  );
}
