1... interface FeatureSelectorProps {
2...   selected: string[];
3...   onChange: (features: string[]) => void;
4... }
5... 
6... export const AVAILABLE_FEATURES = [
7...   { name: 'RECENCY_DAYS', view: 'CUSTOMER_RFM_FV', desc: 'Days since last purchase' },
8...   { name: 'ORDER_FREQUENCY', view: 'CUSTOMER_RFM_FV', desc: 'Total number of orders' },
9...   { name: 'TOTAL_MONETARY', view: 'CUSTOMER_RFM_FV', desc: 'Lifetime spend' },
10...   { name: 'AVG_ORDER_VALUE', view: 'CUSTOMER_RFM_FV', desc: 'Average order value' },
11...   { name: 'BRAND_DIVERSITY', view: 'CUSTOMER_RFM_FV', desc: 'Number of distinct brands purchased' },
12...   { name: 'DISCOUNT_SENSITIVITY', view: 'CUSTOMER_RFM_FV', desc: 'Fraction of orders with discount' },
13...   { name: 'PROREWARDS_FLAG', view: 'CUSTOMER_RFM_FV', desc: 'ProRewards member indicator' },
14...   { name: 'AVG_BASKET_SIZE', view: 'CUSTOMER_BEHAVIOR_FV', desc: 'Average order total' },
15...   { name: 'AVG_BASKET_ITEMS', view: 'CUSTOMER_BEHAVIOR_FV', desc: 'Average items per order' },
16...   { name: 'COUPON_USAGE_RATE', view: 'CUSTOMER_BEHAVIOR_FV', desc: 'Coupon usage frequency' },
17... ];
18... 
19... export default function FeatureSelector({ selected, onChange }: FeatureSelectorProps) {
20...   function toggleFeature(name: string) {
21...     if (selected.includes(name)) {
22...       onChange(selected.filter(f => f !== name));
23...     } else {
24...       onChange([...selected, name]);
25...     }
26...   }
27... 
28...   return (
29...     <div style={{ maxHeight: 200, overflow: 'auto' }}>
30...       {AVAILABLE_FEATURES.map(feat => (
31...         <label key={feat.name} style={{ display: 'flex', alignItems: 'center', padding: '6px 0', cursor: 'pointer', fontSize: 12 }}>
32...           <input
33...             type="checkbox"
34...             checked={selected.includes(feat.name)}
35...             onChange={() => toggleFeature(feat.name)}
36...             style={{ marginRight: 8 }}
37...           />
38...           <div>
39...             <span style={{ fontWeight: 500 }}>{feat.name}</span>
40...             <span style={{ color: '#999', marginLeft: 6 }}>({feat.view})</span>
41...             <div style={{ color: '#666', fontSize: 11 }}>{feat.desc}</div>
42...           </div>
43...         </label>
44...       ))}
45...     </div>
46...   );
47... }
48... 