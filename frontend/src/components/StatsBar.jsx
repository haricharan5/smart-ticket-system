import { Ticket, Clock, CheckCircle, AlertOctagon, Loader } from 'lucide-react'

const STATS = [
  { key: 'total', label: 'Total', icon: Ticket, color: 'text-blue-600 bg-blue-50' },
  { key: 'open', label: 'Open', icon: Clock, color: 'text-yellow-600 bg-yellow-50' },
  { key: 'in_progress', label: 'In Progress', icon: Loader, color: 'text-purple-600 bg-purple-50' },
  { key: 'resolved', label: 'Resolved', icon: CheckCircle, color: 'text-green-600 bg-green-50' },
  { key: 'critical', label: 'Critical', icon: AlertOctagon, color: 'text-red-600 bg-red-50' },
]

export default function StatsBar({ summary }) {
  return (
    <div className="grid grid-cols-5 gap-4 mb-6">
      {STATS.map(({ key, label, icon: Icon, color }) => (
        <div key={key} className="bg-white rounded-xl p-4 shadow-sm border border-gray-100">
          <div className="flex items-center justify-between mb-2">
            <span className="text-xs font-medium text-gray-500 uppercase tracking-wide">{label}</span>
            <span className={`p-1.5 rounded-lg ${color}`}>
              <Icon size={14} />
            </span>
          </div>
          <p className="text-2xl font-bold text-gray-900">{summary?.[key] ?? '—'}</p>
        </div>
      ))}
    </div>
  )
}
