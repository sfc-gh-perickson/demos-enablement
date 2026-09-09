import { useState, useEffect, useRef } from 'react';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Cell } from 'recharts';
import { executeSQL } from '../api/snowflake';
import FeatureSelector, { AVAILABLE_FEATURES } from '../components/FeatureSelector';

const SEGMENTS = ['Champion', 'Engaged', 'Moderate', 'At Risk'];
const BRANDS = ['Peak Hydro', 'ChefLine', 'Ridgeline', 'VitaCare', 'PrimeLine'];
const STATES = ['CA', 'FL', 'GA', 'IL', 'NC', 'NY', 'OH', 'PA', 'TX', 'WA'];

const card: React.CSSProperties = { background: '#fff', borderRadius: 8, padding: 20, marginBottom: 16, boxShadow: '0 1px 3px rgba(0,0,0,0.1)' };
const thSort: React.CSSProperties = { textAlign: 'left', padding: 6, cursor: 'pointer', userSelect: 'none', whiteSpace: 'nowrap' };
const chip = (active: boolean): React.CSSProperties => ({
  display: 'inline-block', padding: '4px 10px', margin: '3px 4px 3px 0', borderRadius: 14, fontSize: 12, cursor: 'pointer',
  border: active ? '2px solid #2563eb' : '1px solid #d1d5db', background: active ? '#eff6ff' : '#fff', fontWeight: active ? 600 : 400,
});

interface ModelResult {
  model_name: string;
  auc: number;
  cv_fold_scores: number[];
  seed_count: number;
  total_scored: number;
  feature_importances: { feature: string; importance: number }[];
  score_distribution: { bucket: string; count: number }[];
  top_lookalikes: { customer_id: string; score: number }[];
}

interface CustomerProfile {
  customer_id: string;
  segment: string;
  ltv: number;
  repurchase: number;
  orders: number;
  spend: number;
  top_brand: string;
  state: string;
}

export default function LookalikeBuilder() {
  const [selSegments, setSelSegments] = useState<string[]>(['Champion']);
  const [selBrands, setSelBrands] = useState<string[]>([]);
  const [selStates, setSelStates] = useState<string[]>([]);
  const [minPurchases, setMinPurchases] = useState(2);
  const [minSpend, setMinSpend] = useState(50);
  const [seedCount, setSeedCount] = useState<number | null>(null);
  const [selectedFeatures, setSelectedFeatures] = useState<string[]>(AVAILABLE_FEATURES.map(f => f.name));
  const [modelName, setModelName] = useState('my_lookalike');
  const [loading, setLoading] = useState(false);
  const [status, setStatus] = useState('');
  const [result, setResult] = useState<ModelResult | null>(null);
  const [profiles, setProfiles] = useState<Map<string, CustomerProfile>>(new Map());
  const [sortKey, setSortKey] = useState<string>('score');
  const [sortAsc, setSortAsc] = useState(false);

  function toggle<T>(arr: T[], val: T): T[] {
    return arr.includes(val) ? arr.filter(v => v !== val) : [...arr, val];
  }

  function buildSeedSQL(mode: 'count' | 'ids'): string {
    const select = mode === 'count' ? 'COUNT(DISTINCT cs.CUSTOMER_ID) AS CNT' : 'DISTINCT cs.CUSTOMER_ID';
    const brandFilter = selBrands.length > 0 ? `AND BRAND IN (${selBrands.map(b => `'${b}'`).join(',')})` : '';
    const stateFilter = selStates.length > 0 ? `AND STATE IN (${selStates.map(s => `'${s}'`).join(',')})` : '';
    const segFilter = selSegments.length > 0 ? `AND cs.SEGMENT_LABEL IN (${selSegments.map(s => `'${s}'`).join(',')})` : '';

    return `
      SELECT ${select}
      FROM SB_COMMAND_CENTER.SCORING.CUSTOMER_SCORES cs
      JOIN (
        SELECT CUSTOMER_ID, COUNT(*) AS purchases, SUM(PURCHASE_AMOUNT) AS total_spend
        FROM SB_COMMAND_CENTER.RAW.CUSTOMER_TRANSACTIONS
        WHERE 1=1 ${brandFilter} ${stateFilter}
        GROUP BY 1
        HAVING purchases >= ${minPurchases} AND total_spend >= ${minSpend}
      ) ct ON cs.CUSTOMER_ID = ct.CUSTOMER_ID
      WHERE 1=1 ${segFilter}
    `;
  }

  const seedSql = buildSeedSQL('count');
  const prevSqlRef = useRef(seedSql);

  useEffect(() => {
    prevSqlRef.current = seedSql;
    const t = setTimeout(async () => {
      try {
        const rows = await executeSQL(seedSql);
        if (prevSqlRef.current === seedSql) {
          setSeedCount(Number((rows[0] as Record<string, string>)?.CNT ?? 0));
        }
      } catch { setSeedCount(null); }
    }, 500);
    return () => clearTimeout(t);
  }, [seedSql]);

  async function buildLookalike() {
    setLoading(true);
    setStatus('Resolving seed audience...');
    setResult(null);
    try {
      const seedRows = await executeSQL(buildSeedSQL('ids'));
      const ids = (seedRows as Record<string, string>[]).map(r => r.CUSTOMER_ID);
      if (ids.length === 0) { setStatus('No customers match the seed criteria.'); setLoading(false); return; }
      if (ids.length > 5000) { setStatus(`Seed too large (${ids.length}). Narrow your filters.`); setLoading(false); return; }

      setStatus(`Training model on ${ids.length} seed customers...`);
      const idsArray = ids.map(id => `'${id}'`).join(',');
      const ts = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14);
      const fullModelName = `${modelName}_${ts}`;
      const viewNames = [...new Set(
        selectedFeatures.map(f => AVAILABLE_FEATURES.find(af => af.name === f)?.view).filter(Boolean)
      )];
      const fvs = viewNames.map(f => `'${f}'`).join(',');
      const procResult = await executeSQL(`
        CALL SB_COMMAND_CENTER.PROCEDURES.BUILD_LOOKALIKE(
          ARRAY_CONSTRUCT(${idsArray}),
          ARRAY_CONSTRUCT(${fvs}),
          '${fullModelName}'
        )
      `);

      const firstRow = procResult[0] as Record<string, string>;
      const jsonStr = firstRow ? Object.values(firstRow)[0] : null;
      if (jsonStr) {
        const parsed: ModelResult = JSON.parse(jsonStr);
        setResult(parsed);
        setStatus(`Model "${parsed.model_name}" built — AUC: ${parsed.auc.toFixed(3)}. Loading profiles...`);

        // Fetch profiles for the top lookalikes
        const topIds = parsed.top_lookalikes.map(l => `'${l.customer_id}'`).join(',');
        const profileRows = await executeSQL(`
          SELECT cs.CUSTOMER_ID, cs.SEGMENT_LABEL, cs.LTV_PREDICTION, cs.REPURCHASE_SCORE,
                 ct.ORDERS, ct.TOTAL_SPEND, ct.TOP_BRAND, ct.STATE
          FROM SB_COMMAND_CENTER.SCORING.CUSTOMER_SCORES cs
          LEFT JOIN (
            SELECT CUSTOMER_ID, COUNT(*) AS ORDERS, ROUND(SUM(PURCHASE_AMOUNT),2) AS TOTAL_SPEND,
                   MAX_BY(BRAND, PURCHASE_AMOUNT) AS TOP_BRAND,
                   MAX_BY(STATE, TRANSACTION_DATE) AS STATE
            FROM SB_COMMAND_CENTER.RAW.CUSTOMER_TRANSACTIONS
            GROUP BY 1
          ) ct ON cs.CUSTOMER_ID = ct.CUSTOMER_ID
          WHERE cs.CUSTOMER_ID IN (${topIds})
        `);
        const pMap = new Map<string, CustomerProfile>();
        for (const r of profileRows as Record<string, string>[]) {
          pMap.set(r.CUSTOMER_ID, {
            customer_id: r.CUSTOMER_ID,
            segment: r.SEGMENT_LABEL || '-',
            ltv: Number(r.LTV_PREDICTION) || 0,
            repurchase: Number(r.REPURCHASE_SCORE) || 0,
            orders: Number(r.ORDERS) || 0,
            spend: Number(r.TOTAL_SPEND) || 0,
            top_brand: r.TOP_BRAND || '-',
            state: r.STATE || '-',
          });
        }
        setProfiles(pMap);
        setStatus(`Model "${parsed.model_name}" built — AUC: ${parsed.auc.toFixed(3)}`);
      } else {
        setStatus('Model built but no stats returned.');
      }
    } catch (err) {
      setStatus(`Error: ${err instanceof Error ? err.message : 'Unknown error'}`);
    } finally {
      setLoading(false);
    }
  }

  function handleSort(key: string) {
    if (key === sortKey) setSortAsc(!sortAsc);
    else { setSortKey(key); setSortAsc(key === 'customer_id'); }
  }

  const sortedLookalikes = result ? [...result.top_lookalikes].sort((a, b) => {
    if (sortKey === 'score') return sortAsc ? a.score - b.score : b.score - a.score;
    if (sortKey === 'customer_id') return sortAsc ? a.customer_id.localeCompare(b.customer_id) : b.customer_id.localeCompare(a.customer_id);
    const pa = profiles.get(a.customer_id);
    const pb = profiles.get(b.customer_id);
    if (!pa || !pb) return 0;
    const va = pa[sortKey as keyof CustomerProfile];
    const vb = pb[sortKey as keyof CustomerProfile];
    const cmp = typeof va === 'number' ? (va as number) - (vb as number) : String(va).localeCompare(String(vb));
    return sortAsc ? cmp : -cmp;
  }) : [];

  const arrow = (key: string) => sortKey === key ? (sortAsc ? ' \u25B2' : ' \u25BC') : '';
  const aucColor = (auc: number) => auc >= 0.8 ? '#10b981' : auc >= 0.7 ? '#f59e0b' : '#ef4444';

  const canBuild = selSegments.length > 0 && selectedFeatures.length > 0 && seedCount !== null && seedCount > 0;

  return (
    <div>
      <h1 style={{ fontSize: 22, marginBottom: 16 }}>Lookalike Audience Builder</h1>
      <p style={{ color: '#666', fontSize: 13, marginBottom: 24 }}>
        Define a customer profile, select ML features, and build a model to find similar customers.
      </p>

      <div style={{ display: 'grid', gridTemplateColumns: '380px 1fr', gap: 24 }}>
        {/* Left column: filters */}
        <div>
          <div style={card}>
            <h3 style={{ fontSize: 14, marginBottom: 12 }}>1. Define Seed Profile</h3>

            <label style={{ fontSize: 12, fontWeight: 600, color: '#374151', display: 'block', marginBottom: 4 }}>Segment</label>
            <div style={{ marginBottom: 12 }}>
              {SEGMENTS.map(s => (
                <span key={s} style={chip(selSegments.includes(s))} onClick={() => setSelSegments(toggle(selSegments, s))}>{s}</span>
              ))}
            </div>

            <label style={{ fontSize: 12, fontWeight: 600, color: '#374151', display: 'block', marginBottom: 4 }}>Brand Affinity</label>
            <div style={{ marginBottom: 12 }}>
              {BRANDS.map(b => (
                <span key={b} style={chip(selBrands.includes(b))} onClick={() => setSelBrands(toggle(selBrands, b))}>{b}</span>
              ))}
            </div>

            <label style={{ fontSize: 12, fontWeight: 600, color: '#374151', display: 'block', marginBottom: 4 }}>State</label>
            <div style={{ marginBottom: 12 }}>
              {STATES.map(s => (
                <span key={s} style={chip(selStates.includes(s))} onClick={() => setSelStates(toggle(selStates, s))}>{s}</span>
              ))}
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 12 }}>
              <div>
                <label style={{ fontSize: 12, fontWeight: 600, color: '#374151' }}>Min Purchases</label>
                <input type="number" value={minPurchases} onChange={e => setMinPurchases(Number(e.target.value))}
                  style={{ width: '100%', padding: 8, border: '1px solid #ddd', borderRadius: 6, fontSize: 13, marginTop: 4 }} />
              </div>
              <div>
                <label style={{ fontSize: 12, fontWeight: 600, color: '#374151' }}>Min Spend ($)</label>
                <input type="number" value={minSpend} onChange={e => setMinSpend(Number(e.target.value))}
                  style={{ width: '100%', padding: 8, border: '1px solid #ddd', borderRadius: 6, fontSize: 13, marginTop: 4 }} />
              </div>
            </div>

            <div style={{ padding: '8px 12px', background: '#f9fafb', borderRadius: 6, fontSize: 13, textAlign: 'center' }}>
              {seedCount === null ? 'Counting...' : <><strong>{seedCount.toLocaleString()}</strong> customers match this profile</>}
            </div>
          </div>

          <div style={card}>
            <h3 style={{ fontSize: 14, marginBottom: 12 }}>2. Select Features</h3>
            <FeatureSelector selected={selectedFeatures} onChange={setSelectedFeatures} />
          </div>

          <div style={card}>
            <h3 style={{ fontSize: 14, marginBottom: 12 }}>3. Model Name</h3>
            <input value={modelName} onChange={e => setModelName(e.target.value)}
              style={{ width: '100%', padding: 10, border: '1px solid #ddd', borderRadius: 6, fontSize: 13 }} />
          </div>

          <button onClick={buildLookalike} disabled={loading || !canBuild}
            style={{
              width: '100%', padding: '12px 24px', background: loading ? '#94a3b8' : !canBuild ? '#cbd5e1' : '#2563eb',
              color: '#fff', border: 'none', borderRadius: 8, cursor: loading || !canBuild ? 'default' : 'pointer',
              fontSize: 14, fontWeight: 500,
            }}>
            {loading ? 'Training...' : 'Build Lookalike Model'}
          </button>
          {status && <p style={{ marginTop: 12, fontSize: 13, color: '#666' }}>{status}</p>}
        </div>

        {/* Right column: results */}
        <div>
          {!result ? (
            <div style={{ ...card, textAlign: 'center', padding: 60, color: '#999' }}>
              <p style={{ fontSize: 14 }}>Define a seed profile and click Build to see model results.</p>
            </div>
          ) : (
            <>
              {/* Metric cards */}
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12, marginBottom: 16 }}>
                <MetricCard label="AUC Score" value={result.auc.toFixed(3)} color={aucColor(result.auc)} />
                <MetricCard label="Seed Size" value={result.seed_count.toLocaleString()} />
                <MetricCard label="Scored" value={result.total_scored.toLocaleString()} />
                <MetricCard label="Top Score" value={result.top_lookalikes[0]?.score.toFixed(4) ?? '-'} />
              </div>

              {/* CV Fold scores */}
              {result.cv_fold_scores && result.cv_fold_scores.length > 0 && (
                <div style={{ ...card, marginBottom: 16 }}>
                  <h3 style={{ fontSize: 13, color: '#666', marginBottom: 4 }}>Cross-Validation AUC by Fold</h3>
                  <div style={{ display: 'flex', gap: 8 }}>
                    {result.cv_fold_scores.map((s, i) => (
                      <span key={i} style={{ fontSize: 12, padding: '4px 10px', background: '#f0fdf4', borderRadius: 6, color: '#166534' }}>
                        Fold {i + 1}: {s.toFixed(3)}
                      </span>
                    ))}
                  </div>
                </div>
              )}

              {/* Charts row */}
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16, marginBottom: 16 }}>
                {/* Feature importance */}
                <div style={card}>
                  <h3 style={{ fontSize: 13, color: '#666', marginBottom: 8 }}>Feature Importance</h3>
                  <ResponsiveContainer width="100%" height={220}>
                    <BarChart data={result.feature_importances.slice(0, 8)} layout="vertical" margin={{ left: 10 }}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis type="number" tick={{ fontSize: 10 }} />
                      <YAxis type="category" dataKey="feature" tick={{ fontSize: 10 }} width={120} />
                      <Tooltip formatter={(v: number) => v.toFixed(4)} />
                      <Bar dataKey="importance" radius={[0, 4, 4, 0]}>
                        {result.feature_importances.slice(0, 8).map((_, i) => (
                          <Cell key={i} fill={i === 0 ? '#2563eb' : i < 3 ? '#60a5fa' : '#93c5fd'} />
                        ))}
                      </Bar>
                    </BarChart>
                  </ResponsiveContainer>
                </div>

                {/* Score distribution */}
                <div style={card}>
                  <h3 style={{ fontSize: 13, color: '#666', marginBottom: 8 }}>Lookalike Score Distribution</h3>
                  <ResponsiveContainer width="100%" height={220}>
                    <BarChart data={result.score_distribution}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis dataKey="bucket" tick={{ fontSize: 10 }} />
                      <YAxis tick={{ fontSize: 10 }} />
                      <Tooltip />
                      <Bar dataKey="count" fill="#f59e0b" radius={[4, 4, 0, 0]} />
                    </BarChart>
                  </ResponsiveContainer>
                </div>
              </div>

              {/* Results table */}
              <div style={card}>
                <h3 style={{ fontSize: 13, color: '#666', marginBottom: 8 }}>Top {result.top_lookalikes.length} Lookalike Customers</h3>
                <div style={{ overflowX: 'auto' }}>
                <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 12 }}>
                  <thead>
                    <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
                      <th style={thSort} onClick={() => handleSort('customer_id')}>Customer{arrow('customer_id')}</th>
                      <th style={{ ...thSort, textAlign: 'right' }} onClick={() => handleSort('score')}>Score{arrow('score')}</th>
                      <th style={{ padding: 6, width: 100 }}>Confidence</th>
                      <th style={thSort} onClick={() => handleSort('segment')}>Segment{arrow('segment')}</th>
                      <th style={{ ...thSort, textAlign: 'right' }} onClick={() => handleSort('ltv')}>LTV{arrow('ltv')}</th>
                      <th style={{ ...thSort, textAlign: 'right' }} onClick={() => handleSort('repurchase')}>Repurchase{arrow('repurchase')}</th>
                      <th style={{ ...thSort, textAlign: 'right' }} onClick={() => handleSort('orders')}>Orders{arrow('orders')}</th>
                      <th style={{ ...thSort, textAlign: 'right' }} onClick={() => handleSort('spend')}>Spend{arrow('spend')}</th>
                      <th style={thSort} onClick={() => handleSort('top_brand')}>Top Brand{arrow('top_brand')}</th>
                      <th style={thSort} onClick={() => handleSort('state')}>State{arrow('state')}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {sortedLookalikes.map((r, i) => {
                      const p = profiles.get(r.customer_id);
                      return (
                        <tr key={i} style={{ borderBottom: '1px solid #f3f4f6' }}>
                          <td style={{ padding: 6 }}>{r.customer_id}</td>
                          <td style={{ padding: 6, textAlign: 'right', fontFamily: 'monospace' }}>{r.score.toFixed(4)}</td>
                          <td style={{ padding: '6px 6px 6px 0' }}>
                            <div style={{ background: '#e5e7eb', borderRadius: 4, height: 14, overflow: 'hidden' }}>
                              <div style={{ width: `${(r.score * 100).toFixed(1)}%`, background: r.score > 0.8 ? '#10b981' : r.score > 0.5 ? '#f59e0b' : '#94a3b8', height: '100%', borderRadius: 4 }} />
                            </div>
                          </td>
                          <td style={{ padding: 6 }}>{p?.segment ?? '-'}</td>
                          <td style={{ padding: 6, textAlign: 'right' }}>{p ? `$${p.ltv.toFixed(0)}` : '-'}</td>
                          <td style={{ padding: 6, textAlign: 'right' }}>{p?.repurchase.toFixed(3) ?? '-'}</td>
                          <td style={{ padding: 6, textAlign: 'right' }}>{p?.orders ?? '-'}</td>
                          <td style={{ padding: 6, textAlign: 'right' }}>{p ? `$${p.spend.toFixed(0)}` : '-'}</td>
                          <td style={{ padding: 6 }}>{p?.top_brand ?? '-'}</td>
                          <td style={{ padding: 6 }}>{p?.state ?? '-'}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
                </div>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

function MetricCard({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <div style={{ background: '#fff', borderRadius: 8, padding: 16, boxShadow: '0 1px 3px rgba(0,0,0,0.1)', textAlign: 'center' }}>
      <div style={{ fontSize: 11, color: '#6b7280', marginBottom: 4 }}>{label}</div>
      <div style={{ fontSize: 22, fontWeight: 700, color: color || '#111827' }}>{value}</div>
    </div>
  );
}
