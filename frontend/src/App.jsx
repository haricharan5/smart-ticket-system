import { BrowserRouter, Routes, Route, NavLink, Navigate, useLocation } from 'react-router-dom'
import { LayoutDashboard, BarChart3, Plus, Ticket } from 'lucide-react'
import { AuthProvider, useAuth } from './context/AuthContext'
import Dashboard from './pages/Dashboard'
import Analytics from './pages/Analytics'
import TicketDetailPage from './pages/TicketDetailPage'
import SubmitTicket from './pages/SubmitTicket'
import Login from './pages/Login'
import OutageBanner from './components/OutageBanner'
import TopBar from './components/TopBar'

const NAV = [
  { to: '/', icon: LayoutDashboard, label: 'Dashboard' },
  { to: '/analytics', icon: BarChart3, label: 'Analytics' },
  { to: '/submit', icon: Plus, label: 'New Ticket' },
]

function Sidebar() {
  return (
    <aside className="w-56 shrink-0 min-h-screen flex flex-col" style={{ backgroundColor: '#141e35' }}>
      <div className="px-6 py-5 border-b border-slate-700">
        <div className="flex items-center gap-2">
          <Ticket className="text-blue-400" size={22} />
          <span className="text-white font-semibold text-sm leading-tight">
            Smart<br />Support
          </span>
        </div>
      </div>
      <nav className="flex-1 px-3 py-4 space-y-1">
        {NAV.map(({ to, icon: Icon, label }) => (
          <NavLink
            key={to}
            to={to}
            end={to === '/'}
            className={({ isActive }) =>
              `flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors ${
                isActive
                  ? 'bg-blue-600 text-white'
                  : 'text-slate-400 hover:text-white hover:bg-slate-700'
              }`
            }
          >
            <Icon size={16} />
            {label}
          </NavLink>
        ))}
      </nav>
      <div className="px-4 py-4 border-t border-slate-700">
        <p className="text-xs text-slate-500">Azure AI · NLP Powered</p>
      </div>
    </aside>
  )
}

function RequireAuth({ children }) {
  const { isAuthenticated } = useAuth()
  const location = useLocation()
  if (!isAuthenticated) {
    return <Navigate to="/login" state={{ from: location }} replace />
  }
  return children
}

function AppShell() {
  return (
    <div className="flex min-h-screen" style={{ backgroundColor: '#141e35' }}>
      <Sidebar />
      <div className="flex-1 flex flex-col bg-gray-50">
        <TopBar />
        <OutageBanner />
        <main className="flex-1 p-6 overflow-auto">
          <Routes>
            <Route path="/" element={<RequireAuth><Dashboard /></RequireAuth>} />
            <Route path="/analytics" element={<RequireAuth><Analytics /></RequireAuth>} />
            <Route path="/submit" element={<RequireAuth><SubmitTicket /></RequireAuth>} />
            <Route path="/tickets/:id" element={<RequireAuth><TicketDetailPage /></RequireAuth>} />
          </Routes>
        </main>
      </div>
    </div>
  )
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route path="/*" element={<AppShell />} />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  )
}
