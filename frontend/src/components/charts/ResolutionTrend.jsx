import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts'

export default function ResolutionTrend({ data }) {
  if (!data?.length) return <p className="text-center text-gray-400 text-sm py-8">No resolved tickets yet</p>
  const formatted = data.map((d) => ({
    category: d.category?.split(' ')[0],
    hours: Math.round((d.avg_minutes || 0) / 60),
  }))
  return (
    <ResponsiveContainer width="100%" height={220}>
      <BarChart data={formatted} margin={{ top: 4, right: 4, left: -20, bottom: 0 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
        <XAxis dataKey="category" tick={{ fontSize: 11 }} />
        <YAxis tick={{ fontSize: 11 }} unit="h" />
        <Tooltip formatter={(v) => [`${v}h`, 'Avg. Resolution']} />
        <Bar dataKey="hours" fill="#8b5cf6" radius={[4, 4, 0, 0]} name="Avg Hours" />
      </BarChart>
    </ResponsiveContainer>
  )
}
