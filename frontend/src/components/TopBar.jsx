import { LogOut, User } from 'lucide-react'
import { useAuth } from '../context/AuthContext'

const ROLE_COLORS = {
  admin: 'bg-purple-100 text-purple-700',
  team_lead: 'bg-blue-100 text-blue-700',
  agent: 'bg-green-100 text-green-700',
}

export default function TopBar() {
  const { user, logout } = useAuth()
  if (!user) return null

  return (
    <div className="h-12 bg-white border-b border-gray-100 px-6 flex items-center justify-between shrink-0">
      <div />
      <div className="flex items-center gap-3">
        <span
          className={`text-xs font-medium px-2 py-0.5 rounded-full ${ROLE_COLORS[user.role] || ROLE_COLORS.agent}`}
        >
          {user.role.replace('_', ' ')}
        </span>
        <div className="flex items-center gap-1.5 text-sm text-gray-700">
          <User size={14} className="text-gray-400" />
          <span className="font-medium">{user.name}</span>
        </div>
        <button
          onClick={logout}
          className="flex items-center gap-1.5 text-xs text-gray-400 hover:text-red-500 transition-colors ml-2"
          title="Sign out"
        >
          <LogOut size={13} />
          Sign out
        </button>
      </div>
    </div>
  )
}
