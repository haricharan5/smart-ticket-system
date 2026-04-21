import { useNavigate } from 'react-router-dom'
import { formatDistanceToNow } from 'date-fns'
import { UrgencyBadge, CategoryBadge, StatusBadge } from './Badges'
import SLATimer from './SLATimer'

export default function TicketQueue({ tickets, loading }) {
  const navigate = useNavigate()

  if (loading) {
    return (
      <div className="flex items-center justify-center h-40 text-gray-400 text-sm">
        Loading tickets...
      </div>
    )
  }

  if (!tickets.length) {
    return (
      <div className="flex items-center justify-center h-40 text-gray-400 text-sm">
        No tickets found.
      </div>
    )
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-gray-200 text-left text-xs text-gray-500 uppercase tracking-wide">
            <th className="pb-3 pr-4 font-medium">ID</th>
            <th className="pb-3 pr-4 font-medium">Title</th>
            <th className="pb-3 pr-4 font-medium">Category</th>
            <th className="pb-3 pr-4 font-medium">Urgency</th>
            <th className="pb-3 pr-4 font-medium">Status</th>
            <th className="pb-3 pr-4 font-medium">Team</th>
            <th className="pb-3 pr-4 font-medium">SLA</th>
            <th className="pb-3 font-medium">Created</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100">
          {tickets.map((t) => (
            <tr
              key={t.id}
              onClick={() => navigate(`/tickets/${t.id}`)}
              className="hover:bg-blue-50 cursor-pointer transition-colors"
            >
              <td className="py-3 pr-4 text-gray-400 font-mono">#{t.id}</td>
              <td className="py-3 pr-4 font-medium text-gray-900 max-w-xs truncate">{t.title}</td>
              <td className="py-3 pr-4">
                {t.category ? <CategoryBadge category={t.category} /> : <span className="text-gray-300">—</span>}
              </td>
              <td className="py-3 pr-4">
                {t.urgency ? <UrgencyBadge urgency={t.urgency} /> : <span className="text-gray-300">—</span>}
              </td>
              <td className="py-3 pr-4">
                <StatusBadge status={t.status} />
              </td>
              <td className="py-3 pr-4 text-gray-600 text-xs truncate max-w-[120px]">
                {t.team || '—'}
              </td>
              <td className="py-3 pr-4">
                <SLATimer slaDeadline={t.sla_deadline} status={t.status} />
              </td>
              <td className="py-3 text-gray-400 text-xs whitespace-nowrap">
                {t.created_at ? formatDistanceToNow(new Date(t.created_at), { addSuffix: true }) : '—'}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
