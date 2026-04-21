import { useEffect, useState, useCallback } from 'react'
import { RefreshCw } from 'lucide-react'
import { api } from '../api/tickets'
import StatsBar from '../components/StatsBar'
import TicketQueue from '../components/TicketQueue'

const STATUSES = ['', 'open', 'in_progress', 'resolved']
const CATEGORIES = ['', 'Technical Issue', 'Billing Query', 'General Inquiry', 'HR/Internal', 'Other']

export default function Dashboard() {
  const [tickets, setTickets] = useState([])
  const [summary, setSummary] = useState(null)
  const [loading, setLoading] = useState(true)
  const [statusFilter, setStatusFilter] = useState('')
  const [categoryFilter, setCategoryFilter] = useState('')

  const load = useCallback(() => {
    Promise.all([
      api.tickets.list({ status: statusFilter || undefined, category: categoryFilter || undefined }),
      api.analytics.summary(),
    ])
      .then(([t, s]) => { setTickets(t); setSummary(s) })
      .catch(console.error)
      .finally(() => setLoading(false))
  }, [statusFilter, categoryFilter])

  useEffect(() => {
    setLoading(true)
    load()
    const id = setInterval(load, 3000)
    return () => clearInterval(id)
  }, [load])

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Support Dashboard</h1>
          <p className="text-sm text-gray-500 mt-0.5">Live ticket queue · auto-refreshes every 3s</p>
        </div>
        <button onClick={load} className="flex items-center gap-2 text-sm text-gray-500 hover:text-blue-600 transition-colors">
          <RefreshCw size={14} />
          Refresh
        </button>
      </div>

      <StatsBar summary={summary} />

      <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-6">
        <div className="flex items-center justify-between mb-4">
          <h2 className="font-semibold text-gray-900">Ticket Queue</h2>
          <div className="flex gap-3">
            <select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value)}
              className="text-xs border border-gray-200 rounded-lg px-3 py-1.5 focus:outline-none focus:ring-2 focus:ring-blue-500"
            >
              {STATUSES.map((s) => <option key={s} value={s}>{s || 'All Statuses'}</option>)}
            </select>
            <select
              value={categoryFilter}
              onChange={(e) => setCategoryFilter(e.target.value)}
              className="text-xs border border-gray-200 rounded-lg px-3 py-1.5 focus:outline-none focus:ring-2 focus:ring-blue-500"
            >
              {CATEGORIES.map((c) => <option key={c} value={c}>{c || 'All Categories'}</option>)}
            </select>
          </div>
        </div>
        <TicketQueue tickets={tickets} loading={loading} />
      </div>
    </div>
  )
}
