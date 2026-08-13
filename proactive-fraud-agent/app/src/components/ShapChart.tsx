'use client';

import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Cell, ResponsiveContainer, LabelList } from 'recharts';

interface ShapFactor {
  feature: string;
  shap_value: number;
  direction: string;
}

function formatFeatureName(name: string): string {
  return name
    .replace(/_/g, ' ')
    .replace(/\b(7d|24h|1h)\b/gi, (m) => `(${m.toUpperCase()})`)
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

export function ShapChart({ factors }: { factors: ShapFactor[] }) {
  const data = factors
    .sort((a, b) => Math.abs(b.shap_value) - Math.abs(a.shap_value))
    .map((f) => ({
      name: formatFeatureName(f.feature),
      value: parseFloat(f.shap_value.toFixed(3)),
      direction: f.direction,
    }));

  const chartHeight = Math.max(220, data.length * 36 + 40);

  return (
    <div className="bg-sf-card rounded-lg border border-sf-border p-5">
      <h3 className="text-sm font-semibold text-sf-text-muted mb-4">SHAP Feature Contributions</h3>
      <ResponsiveContainer width="100%" height={chartHeight}>
        <BarChart data={data} layout="vertical" margin={{ left: 10, right: 50 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="var(--sf-border)" horizontal={false} />
          <XAxis type="number" tick={{ fill: '#8BA3BD', fontSize: 11 }} axisLine={{ stroke: 'var(--sf-border)' }} />
          <YAxis
            type="category"
            dataKey="name"
            tick={{ fill: '#E8F0F8', fontSize: 12 }}
            width={140}
            axisLine={false}
            tickLine={false}
          />
          <Tooltip
            contentStyle={{ background: 'var(--sf-card)', border: '1px solid var(--sf-border)', borderRadius: 8 }}
            labelStyle={{ color: '#E8F0F8' }}
            formatter={(value: number) => [value.toFixed(3), 'SHAP Value']}
          />
          <Bar dataKey="value" radius={[0, 4, 4, 0]} barSize={20}>
            {data.map((entry, i) => (
              <Cell
                key={i}
                fill={entry.direction === 'increases_risk' ? '#ef4444' : '#22c55e'}
              />
            ))}
            <LabelList
              dataKey="value"
              position="right"
              style={{ fill: '#8BA3BD', fontSize: 11 }}
              formatter={(v: number) => v.toFixed(2)}
            />
          </Bar>
        </BarChart>
      </ResponsiveContainer>
      <div className="flex gap-4 mt-3 text-xs text-sf-text-muted">
        <span className="flex items-center gap-1.5">
          <span className="w-3 h-3 rounded-sm bg-red-500 inline-block" /> Increases Risk
        </span>
        <span className="flex items-center gap-1.5">
          <span className="w-3 h-3 rounded-sm bg-green-500 inline-block" /> Decreases Risk
        </span>
      </div>
    </div>
  );
}
