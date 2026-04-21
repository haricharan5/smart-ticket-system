import { useEffect, useState } from 'react'
import { AlertTriangle, X } from 'lucide-react'
import { api } from '../api/tickets'

export default function OutageBanner() {
  const [flags, setFlags] = useState([])

  useEffect(() => {
    const fetch = () => api.alerts.outage().then(setFlags).catch(() => {})
    fetch()
    const id = setInterval(fetch, 5000)
    return () => clearInterval(id)
  }, [])

  if (!flags.length) return null

  return (
    <div className="bg-red-600 text-white px-6 py-2 flex items-center gap-3 flex-wrap">
      <AlertTriangle size={16} className="shrink-0" />
      <span className="text-sm font-semibold">OUTAGE DETECTED:</span>
      {flags.map((f) => (
        <span key={f.id} className="flex items-center gap-2 text-sm bg-red-700 rounded px-2 py-0.5">
          {f.category} — {f.ticket_count} tickets in 30 min
          <button
            onClick={() => api.alerts.resolveOutage(f.id).then(() => setFlags((p) => p.filter((x) => x.id !== f.id)))}
            className="hover:text-red-200"
          >
            <X size={13} />
          </button>
        </span>
      ))}
    </div>
  )
}
