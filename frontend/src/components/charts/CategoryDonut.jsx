import { PieChart, Pie, Cell, Tooltip, Legend, ResponsiveContainer } from 'recharts'

const COLORS = ['#3b82f6', '#8b5cf6', '#14b8a6', '#ec4899', '#94a3b8']

export default function CategoryDonut({ data }) {
  if (!data?.length) return <p className="text-center text-gray-400 text-sm py-8">No data</p>
  return (
    <ResponsiveContainer width="100%" height={260}>
      <PieChart>
        <Pie data={data} dataKey="count" nameKey="category" cx="50%" cy="50%" innerRadius={60} outerRadius={100} paddingAngle={3}>
          {data.map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
        </Pie>
        <Tooltip formatter={(v) => [v, 'Tickets']} />
        <Legend formatter={(v) => <span className="text-xs text-gray-600">{v}</span>} />
      </PieChart>
    </ResponsiveContainer>
  )
}
