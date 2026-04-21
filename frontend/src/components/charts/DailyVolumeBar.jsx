import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts'
import { format, parseISO } from 'date-fns'

export default function DailyVolumeBar({ data }) {
  if (!data?.length) return <p className="text-center text-gray-400 text-sm py-8">No data</p>
  const formatted = data.map((d) => ({ ...d, day: format(parseISO(d.day), 'MMM d') }))
  return (
    <ResponsiveContainer width="100%" height={220}>
      <BarChart data={formatted} margin={{ top: 4, right: 4, left: -20, bottom: 0 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
        <XAxis dataKey="day" tick={{ fontSize: 11 }} />
        <YAxis tick={{ fontSize: 11 }} allowDecimals={false} />
        <Tooltip />
        <Bar dataKey="count" fill="#3b82f6" radius={[4, 4, 0, 0]} name="Tickets" />
      </BarChart>
    </ResponsiveContainer>
  )
}
