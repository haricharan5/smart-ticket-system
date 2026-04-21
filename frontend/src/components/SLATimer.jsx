import { useEffect, useState } from 'react'
import { Clock } from 'lucide-react'

function formatSeconds(s) {
  if (s <= 0) return 'BREACHED'
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const sec = s % 60
  if (h > 0) return `${h}h ${m}m`
  if (m > 0) return `${m}m ${sec}s`
  return `${sec}s`
}

export default function SLATimer({ slaDeadline, status }) {
  const [remaining, setRemaining] = useState(0)

  useEffect(() => {
    if (!slaDeadline || status === 'resolved') return
    const calc = () => {
      const diff = Math.floor((new Date(slaDeadline) - Date.now()) / 1000)
      setRemaining(diff)
    }
    calc()
    const id = setInterval(calc, 1000)
    return () => clearInterval(id)
  }, [slaDeadline, status])

  if (!slaDeadline || status === 'resolved') return null

  const isBreached = remaining <= 0
  const isWarning = remaining > 0 && remaining <= 1800

  return (
    <span
      className={`inline-flex items-center gap-1 text-xs font-mono px-2 py-0.5 rounded ${
        isBreached
          ? 'bg-red-100 text-red-700 animate-pulse'
          : isWarning
          ? 'bg-orange-100 text-orange-700'
          : 'bg-gray-100 text-gray-600'
      }`}
    >
      <Clock size={11} />
      {formatSeconds(remaining)}
    </span>
  )
}
