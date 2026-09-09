import { useEffect, useState } from 'react';
import { PieChart, Pie, Cell, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { executeSQL } from '../api/snowflake';

interface SegmentData {
  SEGMENT_LABEL: string;
  CUSTOMERS: number;
  AVG_REPURCHASE_SCORE: number;
  AVG_LTV: number;
}

interface CustomerRow {
  CUSTOMER_ID: string;
  SCORE: number;
  LTV: number;
  SEGMENT_LABEL: string;
}

const COLORS = ['#10b981', '#3b82f6', '#f59e0b', '#ef4444'];

type SortKey = 'CUSTOMER_ID' | 'SCORE' | 'LTV' | 'SEGMENT_LABEL';

export default function CustomerIntelligence() {
  const [segments, setSegments] = useState<SegmentData[]>([]);
  const [customers, setCustomers] = useState<CustomerRow[]>([]);
  const [sortKey, setSortKey] = useState<SortKey>('LTV');
  const [sortAsc, setSortAsc] = useState(false);
  const [segmentFilter, setSegmentFilter] = useState<string>('All');

  useEffect(() => { loadData(); }, []);

  async function loadData() {
    const [segData, custData] = await Promise.all([
      executeSQL(`
        SELECT SEGMENT_LABEL, COUNT(*) AS CUSTOMERS,
               ROUND(AVG(REPURCHASE_SCORE), 3) AS AVG_REPURCHASE_SCORE,
               ROUND(AVG(LTV_PREDICTION), 2) AS AVG_LTV
        FROM SB_COMMAND_CENTER.SCORING.CUSTOMER_SCORES
        GROUP BY 1 ORDER BY AVG_REPURCHASE_SCORE DESC
      `),
      executeSQL(`
        SELECT CUSTOMER_ID, ROUND(REPURCHASE_SCORE, 3) AS SCORE,
               ROUND(LTV_PREDICTION, 2) AS LTV, SEGMENT_LABEL
        FROM SB_COMMAND_CENTER.SCORING.CUSTOMER_SCORES
        ORDER BY LTV_PREDICTION DESC LIMIT 50
      `),
    ]);

    setSegments((segData as Record<string, string>[]).map(r => ({
      SEGMENT_LABEL: r.SEGMENT_LABEL,
      CUSTOMERS: Number(r.CUSTOMERS),
      AVG_REPURCHASE_SCORE: Number(r.AVG_REPURCHASE_SCORE),
      AVG_LTV: Number(r.AVG_LTV),
    })));

    setCustomers((custData as Record<string, string>[]).map(r => ({
      CUSTOMER_ID: r.CUSTOMER_ID,
      SCORE: Number(r.SCORE),
      LTV: Number(r.LTV),
      SEGMENT_LABEL: r.SEGMENT_LABEL,
    })));
  }

  function handleSort(key: SortKey) {
    if (key === sortKey) {
      setSortAsc(!sortAsc);
    } else {
      setSortKey(key);
      setSortAsc(key === 'CUSTOMER_ID' || key === 'SEGMENT_LABEL');
    }
  }

  const filtered = segmentFilter === 'All' ? customers : customers.filter(c => c.SEGMENT_LABEL === segmentFilter);
  const sorted = [...filtered].sort((a, b) => {
    const av = a[sortKey], bv = b[sortKey];
    const cmp = typeof av === 'number' ? (av as number) - (bv as number) : String(av).localeCompare(String(bv));
    return sortAsc ? cmp : -cmp;
  });

  const arrow = (key: SortKey) => sortKey === key ? (sortAsc ? ' \u25B2' : ' \u25BC') : '';
  const thStyle = (align: string): React.CSSProperties => ({
    textAlign: align as 'left' | 'right', padding: 8, cursor: 'pointer', userSelect: 'none',
  });

  return (
    <div>
      <h1 style={{ fontSize: 22, marginBottom: 16 }}>Customer Intelligence</h1>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20, marginBottom: 24 }}>
        <div style={{ background: '#fff', borderRadius: 8, padding: 20, boxShadow: '0 1px 3px rgba(0,0,0,0.1)' }}>
          <h3 style={{ fontSize: 14, color: '#666', marginBottom: 12 }}>Segment Distribution</h3>
          <ResponsiveContainer width="100%" height={250}>
            <PieChart>
              <Pie data={segments} dataKey="CUSTOMERS" nameKey="SEGMENT_LABEL" cx="50%" cy="50%" outerRadius={90}
                label={({ SEGMENT_LABEL, percent }) => `${SEGMENT_LABEL} (${(percent * 100).toFixed(0)}%)`}>
                {segments.map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
              </Pie>
              <Tooltip formatter={(v: number) => v.toLocaleString()} />
              <Legend />
            </PieChart>
          </ResponsiveContainer>
        </div>

        <div style={{ background: '#fff', borderRadius: 8, padding: 20, boxShadow: '0 1px 3px rgba(0,0,0,0.1)' }}>
          <h3 style={{ fontSize: 14, color: '#666', marginBottom: 12 }}>Avg LTV by Segment</h3>
          <ResponsiveContainer width="100%" height={250}>
            <BarChart data={segments}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="SEGMENT_LABEL" tick={{ fontSize: 11 }} />
              <YAxis tick={{ fontSize: 11 }} tickFormatter={v => `$${v.toLocaleString()}`} />
              <Tooltip formatter={(v: number) => `$${v.toLocaleString()}`} />
              <Bar dataKey="AVG_LTV" fill="#3b82f6" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>

      <div style={{ background: '#fff', borderRadius: 8, padding: 20, boxShadow: '0 1px 3px rgba(0,0,0,0.1)' }}>
        <h3 style={{ fontSize: 14, color: '#666', marginBottom: 12 }}>Top Customers by LTV (click headers to sort)</h3>
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
          <thead>
            <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
              <th style={thStyle('left')} onClick={() => handleSort('CUSTOMER_ID')}>Customer ID{arrow('CUSTOMER_ID')}</th>
              <th style={thStyle('right')} onClick={() => handleSort('SCORE')}>Repurchase Score{arrow('SCORE')}</th>
              <th style={thStyle('right')} onClick={() => handleSort('LTV')}>LTV{arrow('LTV')}</th>
              <th style={thStyle('left')}>
                <span style={{ cursor: 'pointer' }} onClick={() => handleSort('SEGMENT_LABEL')}>Segment{arrow('SEGMENT_LABEL')}</span>
                <select value={segmentFilter} onChange={e => setSegmentFilter(e.target.value)}
                  style={{ marginLeft: 6, padding: '2px 4px', borderRadius: 4, border: '1px solid #ccc', fontSize: 11 }}>
                  <option value="All">All</option>
                  {segments.map(s => <option key={s.SEGMENT_LABEL} value={s.SEGMENT_LABEL}>{s.SEGMENT_LABEL}</option>)}
                </select>
              </th>
            </tr>
          </thead>
          <tbody>
            {sorted.map((c, i) => (
              <tr key={i} style={{ borderBottom: '1px solid #f3f4f6' }}>
                <td style={{ padding: 8 }}>{c.CUSTOMER_ID}</td>
                <td style={{ padding: 8, textAlign: 'right' }}>{c.SCORE.toFixed(3)}</td>
                <td style={{ padding: 8, textAlign: 'right' }}>${c.LTV.toLocaleString()}</td>
                <td style={{ padding: 8 }}>{c.SEGMENT_LABEL}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
