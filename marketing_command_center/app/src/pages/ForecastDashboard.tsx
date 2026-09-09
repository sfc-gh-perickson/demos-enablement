import { useEffect, useState } from 'react';
import {
  LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend,
  ResponsiveContainer, Area, ComposedChart, Cell,
} from 'recharts';
import { executeSQL } from '../api/snowflake';

const card: React.CSSProperties = { background: '#fff', borderRadius: 8, padding: 20, boxShadow: '0 1px 3px rgba(0,0,0,0.1)' };

interface ChartPoint { date: string; label: string; actual?: number; forecast?: number; }
interface KPIs { lastWeekUnits: number; lastWeekRevenue: number; returnRate: number; markdownRate: number; forecastTotal: number; }
interface BrandRow { brand: string; units: number; revenue: number; wow: number; }

const RETAILERS = ['Walmart', 'Target', 'Ulta', 'Home Depot', 'Kohls'];
const BRANDS = ['Peak Hydro', 'ChefLine', 'Ridgeline', 'VitaCare', 'PrimeLine'];

export default function ForecastDashboard() {
  const [chartData, setChartData] = useState<ChartPoint[]>([]);
  const [kpis, setKpis] = useState<KPIs | null>(null);
  const [brandBreakdown, setBrandBreakdown] = useState<BrandRow[]>([]);
  const [selectedRetailer, setSelectedRetailer] = useState('Walmart');
  const [selectedBrand, setSelectedBrand] = useState('Peak Hydro');

  useEffect(() => { loadData(); }, [selectedRetailer, selectedBrand]);

  async function loadData() {
    const [fData, aData, kpiData, brandData] = await Promise.all([
      executeSQL(`
        SELECT FORECAST_DATE, ROUND(FORECASTED_UNITS) AS FORECASTED_UNITS
        FROM SB_COMMAND_CENTER.SCORING.DEMAND_FORECASTS
        WHERE RETAILER_NAME = '${selectedRetailer}' AND ITEM_BRAND = '${selectedBrand}'
        ORDER BY FORECAST_DATE
      `),
      executeSQL(`
        SELECT RETAILER_DATE, SUM(GROSS_AMT_SOLD_UNITS) AS GROSS_UNITS_SOLD
        FROM SB_COMMAND_CENTER.RAW.POS_SALES
        WHERE RETAILER_NAME = '${selectedRetailer}' AND ITEM_BRAND = '${selectedBrand}'
        GROUP BY RETAILER_DATE ORDER BY RETAILER_DATE DESC LIMIT 12
      `),
      executeSQL(`
        SELECT
          (SELECT SUM(GROSS_AMT_SOLD_UNITS) FROM SB_COMMAND_CENTER.RAW.POS_SALES
           WHERE RETAILER_NAME='${selectedRetailer}' AND ITEM_BRAND='${selectedBrand}'
             AND RETAILER_DATE = (SELECT MAX(RETAILER_DATE) FROM SB_COMMAND_CENTER.RAW.POS_SALES WHERE RETAILER_NAME='${selectedRetailer}' AND ITEM_BRAND='${selectedBrand}')
          ) AS LAST_WEEK_UNITS,
          (SELECT SUM(GROSS_SALES_RETAIL) FROM SB_COMMAND_CENTER.RAW.POS_SALES
           WHERE RETAILER_NAME='${selectedRetailer}' AND ITEM_BRAND='${selectedBrand}'
             AND RETAILER_DATE = (SELECT MAX(RETAILER_DATE) FROM SB_COMMAND_CENTER.RAW.POS_SALES WHERE RETAILER_NAME='${selectedRetailer}' AND ITEM_BRAND='${selectedBrand}')
          ) AS LAST_WEEK_REVENUE,
          ROUND(SUM(CUSTOMER_RETURN_UNITS) / NULLIF(SUM(GROSS_AMT_SOLD_UNITS), 0) * 100, 1) AS RETURN_RATE,
          ROUND(SUM(TOTAL_MARKDOWN) / NULLIF(SUM(GROSS_SALES_RETAIL), 0) * 100, 1) AS MARKDOWN_RATE
        FROM SB_COMMAND_CENTER.RAW.POS_SALES
        WHERE RETAILER_NAME = '${selectedRetailer}' AND ITEM_BRAND = '${selectedBrand}'
      `),
      executeSQL(`
        WITH latest AS (
          SELECT MAX(RETAILER_DATE) AS max_dt FROM SB_COMMAND_CENTER.RAW.POS_SALES WHERE RETAILER_NAME='${selectedRetailer}'
        ),
        curr AS (
          SELECT ITEM_BRAND, SUM(GROSS_AMT_SOLD_UNITS) AS units, SUM(GROSS_SALES_RETAIL) AS revenue
          FROM SB_COMMAND_CENTER.RAW.POS_SALES, latest
          WHERE RETAILER_NAME='${selectedRetailer}' AND RETAILER_DATE = max_dt GROUP BY 1
        ),
        prev AS (
          SELECT ITEM_BRAND, SUM(GROSS_SALES_RETAIL) AS revenue
          FROM SB_COMMAND_CENTER.RAW.POS_SALES, latest
          WHERE RETAILER_NAME='${selectedRetailer}' AND RETAILER_DATE = DATEADD(week, -1, max_dt) GROUP BY 1
        )
        SELECT c.ITEM_BRAND, c.units, c.revenue,
               ROUND((c.revenue - p.revenue) / NULLIF(p.revenue, 0) * 100, 1) AS WOW
        FROM curr c LEFT JOIN prev p ON c.ITEM_BRAND = p.ITEM_BRAND
        ORDER BY c.revenue DESC
      `),
    ]);

    // Chart data
    const byDate = new Map<string, ChartPoint>();
    for (const row of (aData as Record<string, string>[]).reverse()) {
      const d = toISODate(row.RETAILER_DATE);
      byDate.set(d, { date: d, label: formatDate(row.RETAILER_DATE), actual: Number(row.GROSS_UNITS_SOLD) });
    }
    let forecastTotal = 0;
    for (const row of fData as Record<string, string>[]) {
      const d = toISODate(row.FORECAST_DATE);
      const existing = byDate.get(d) || { date: d, label: formatDate(row.FORECAST_DATE) };
      existing.forecast = Number(row.FORECASTED_UNITS);
      forecastTotal += existing.forecast;
      byDate.set(d, existing);
    }
    const points = [...byDate.values()];
    const lastActualIdx = points.reduce((acc, p, i) => (p.actual !== undefined ? i : acc), -1);
    if (lastActualIdx >= 0 && lastActualIdx < points.length - 1 && points[lastActualIdx].forecast === undefined) {
      points[lastActualIdx].forecast = points[lastActualIdx].actual;
    }
    setChartData(points);

    // KPIs
    const k = kpiData[0] as Record<string, string> | undefined;
    if (k) {
      setKpis({
        lastWeekUnits: Number(k.LAST_WEEK_UNITS) || 0,
        lastWeekRevenue: Number(k.LAST_WEEK_REVENUE) || 0,
        returnRate: Number(k.RETURN_RATE) || 0,
        markdownRate: Number(k.MARKDOWN_RATE) || 0,
        forecastTotal,
      });
    }

    // Brand breakdown
    setBrandBreakdown((brandData as Record<string, string>[]).map(r => ({
      brand: r.ITEM_BRAND,
      units: Number(r.UNITS) || 0,
      revenue: Number(r.REVENUE) || 0,
      wow: Number(r.WOW) || 0,
    })));
  }

  return (
    <div>
      <h1 style={{ fontSize: 22, marginBottom: 16 }}>Demand Forecast Dashboard</h1>

      <div style={{ display: 'flex', gap: 12, marginBottom: 20 }}>
        <select value={selectedRetailer} onChange={e => setSelectedRetailer(e.target.value)}
          style={{ padding: '8px 12px', borderRadius: 6, border: '1px solid #ddd', fontSize: 13 }}>
          {RETAILERS.map(r => <option key={r} value={r}>{r}</option>)}
        </select>
        <select value={selectedBrand} onChange={e => setSelectedBrand(e.target.value)}
          style={{ padding: '8px 12px', borderRadius: 6, border: '1px solid #ddd', fontSize: 13 }}>
          {BRANDS.map(b => <option key={b} value={b}>{b}</option>)}
        </select>
      </div>

      {/* KPI Cards */}
      {kpis && (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: 12, marginBottom: 20 }}>
          <KPI label="Last Week Units" value={kpis.lastWeekUnits.toLocaleString()} />
          <KPI label="Last Week Revenue" value={`$${(kpis.lastWeekRevenue / 1000).toFixed(0)}K`} />
          <KPI label="8-Wk Forecast" value={`${(kpis.forecastTotal / 1000).toFixed(0)}K units`} />
          <KPI label="Return Rate" value={`${kpis.returnRate}%`} color={kpis.returnRate > 6 ? '#ef4444' : '#10b981'} />
          <KPI label="Markdown Rate" value={`${kpis.markdownRate}%`} color={kpis.markdownRate > 6 ? '#f59e0b' : '#10b981'} />
        </div>
      )}

      {/* Main chart */}
      <div style={{ ...card, marginBottom: 20 }}>
        <h3 style={{ fontSize: 14, color: '#666', marginBottom: 12 }}>
          {selectedRetailer} &times; {selectedBrand} — Actual vs 8-Week Forecast
        </h3>
        <ResponsiveContainer width="100%" height={320}>
          <ComposedChart data={chartData}>
            <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
            <XAxis dataKey="label" tick={{ fontSize: 11 }} />
            <YAxis tick={{ fontSize: 11 }} tickFormatter={v => `${(v / 1000).toFixed(0)}K`} />
            <Tooltip
              labelFormatter={(_, payload) => payload?.[0]?.payload?.date || ''}
              formatter={(v: number) => v.toLocaleString()}
            />
            <Legend />
            <Area type="monotone" dataKey="actual" fill="#dbeafe" stroke="none" legendType="none" />
            <Line type="monotone" dataKey="actual" stroke="#2563eb" strokeWidth={2.5} dot={{ r: 3, fill: '#2563eb' }} name="Actual Units" connectNulls={false} />
            <Line type="monotone" dataKey="forecast" stroke="#f59e0b" strokeWidth={2.5} strokeDasharray="6 3" dot={{ r: 3, fill: '#f59e0b' }} name="Forecast" connectNulls={false} />
          </ComposedChart>
        </ResponsiveContainer>
      </div>

      {/* Brand breakdown for the retailer */}
      <div style={{ ...card }}>
        <h3 style={{ fontSize: 14, color: '#666', marginBottom: 12 }}>
          All Brands at {selectedRetailer} — Latest Week
        </h3>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={brandBreakdown} layout="vertical" margin={{ left: 10 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
              <XAxis type="number" tick={{ fontSize: 10 }} tickFormatter={v => `$${(v / 1000).toFixed(0)}K`} />
              <YAxis type="category" dataKey="brand" tick={{ fontSize: 11 }} width={90} />
              <Tooltip formatter={(v: number) => `$${v.toLocaleString()}`} />
              <Bar dataKey="revenue" radius={[0, 4, 4, 0]}>
                {brandBreakdown.map((b, i) => (
                  <Cell key={i} fill={b.brand === selectedBrand ? '#2563eb' : '#93c5fd'} />
                ))}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 12, alignSelf: 'start' }}>
            <thead>
              <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
                <th style={{ textAlign: 'left', padding: 8 }}>Brand</th>
                <th style={{ textAlign: 'right', padding: 8 }}>Units</th>
                <th style={{ textAlign: 'right', padding: 8 }}>Revenue</th>
                <th style={{ textAlign: 'right', padding: 8 }}>WoW</th>
              </tr>
            </thead>
            <tbody>
              {brandBreakdown.map((b, i) => (
                <tr key={i} style={{ borderBottom: '1px solid #f3f4f6', fontWeight: b.brand === selectedBrand ? 600 : 400 }}>
                  <td style={{ padding: 8 }}>{b.brand}</td>
                  <td style={{ padding: 8, textAlign: 'right' }}>{b.units.toLocaleString()}</td>
                  <td style={{ padding: 8, textAlign: 'right' }}>${(b.revenue / 1000).toFixed(0)}K</td>
                  <td style={{ padding: 8, textAlign: 'right', color: b.wow >= 0 ? '#10b981' : '#ef4444' }}>
                    {b.wow >= 0 ? '+' : ''}{b.wow}%
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

function KPI({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <div style={{ background: '#fff', borderRadius: 8, padding: 16, boxShadow: '0 1px 3px rgba(0,0,0,0.1)', textAlign: 'center' }}>
      <div style={{ fontSize: 11, color: '#6b7280', marginBottom: 4 }}>{label}</div>
      <div style={{ fontSize: 20, fontWeight: 700, color: color || '#111827' }}>{value}</div>
    </div>
  );
}

function epochDaysToDate(val: string): Date {
  const days = parseInt(val, 10);
  if (!isNaN(days) && days > 10000 && days < 100000) return new Date(days * 86400000);
  return new Date(val + 'T00:00:00');
}

function formatDate(val: string): string {
  return epochDaysToDate(val).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

function toISODate(val: string): string {
  return epochDaysToDate(val).toISOString().slice(0, 10);
}
