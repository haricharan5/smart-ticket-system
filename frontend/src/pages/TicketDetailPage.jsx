import { useEffect, useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { ArrowLeft, Bot, Send, Save, CheckCircle2 } from 'lucide-react'
import { format } from 'date-fns'
import { api } from '../api/tickets'
import { UrgencyBadge, CategoryBadge, StatusBadge, SentimentBadge } from '../components/Badges'
import SLATimer from '../components/SLATimer'

const CATEGORIES = ['Technical Issue', 'Billing Query', 'General Inquiry', 'HR/Internal', 'Other']
const STATUSES = ['open', 'in_progress', 'resolved']

export default function TicketDetailPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const [ticket, setTicket]     = useState(null)
  const [loading, setLoading]   = useState(true)
  const [reply, setReply]       = useState('')
  const [saving, setSaving]     = useState(false)
  const [sending, setSending]   = useState(false)
  const [replySent, setReplySent] = useState(false)
  const [saveMsg, setSaveMsg]   = useState('')

  const load = () =>
    api.tickets.get(id)
      .then(t => { setTicket(t); setReply(t.ai_draft_reply || '') })
      .catch(() => {})
      .finally(() => setLoading(false))

  useEffect(() => { load() }, [id])

  const updateStatus = async (status) => {
    const updated = await api.tickets.updateStatus(id, status)
    setTicket(updated)
  }

  const overrideCategory = async (category) => {
    const updated = await api.tickets.overrideCategory(id, category)
    setTicket(updated)
  }

  const saveDraft = async () => {
    if (!reply.trim()) return
    setSaving(true)
    try {
      const updated = await api.tickets.updateReply(id, reply)
      setTicket(updated)
      setSaveMsg('Draft saved')
      setTimeout(() => setSaveMsg(''), 2500)
    } catch {
      setSaveMsg('Save failed')
      setTimeout(() => setSaveMsg(''), 2500)
    } finally {
      setSaving(false)
    }
  }

  const sendReply = async () => {
    if (!reply.trim()) return
    setSending(true)
    try {
      // Save the final reply text
      await api.tickets.updateReply(id, reply)
      // Move ticket to in_progress if still open
      if (ticket.status === 'open') {
        const updated = await api.tickets.updateStatus(id, 'in_progress')
        setTicket(updated)
      }
      setReplySent(true)
    } catch {
      setSaveMsg('Send failed — try again')
      setTimeout(() => setSaveMsg(''), 2500)
    } finally {
      setSending(false)
    }
  }

  if (loading) return <div className="text-gray-400 text-sm p-8">Loading...</div>
  if (!ticket)  return <div className="text-red-500 text-sm p-8">Ticket not found.</div>

  return (
    <div className="max-w-3xl">
      <button
        onClick={() => navigate(-1)}
        className="flex items-center gap-2 text-sm text-gray-500 hover:text-gray-900 mb-5 transition-colors"
      >
        <ArrowLeft size={15} /> Back
      </button>

      {/* Ticket Info */}
      <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-6 mb-4">
        <div className="flex items-start justify-between gap-4 mb-4">
          <div>
            <p className="text-xs text-gray-400 font-mono mb-1">#{ticket.id}</p>
            <h1 className="text-xl font-bold text-gray-900">{ticket.title}</h1>
            <p className="text-xs text-gray-400 mt-1">
              {ticket.submitter_email} · {ticket.created_at && format(new Date(ticket.created_at), 'PPp')}
            </p>
          </div>
          <SLATimer slaDeadline={ticket.sla_deadline} status={ticket.status} />
        </div>

        <div className="flex flex-wrap gap-2 mb-5">
          {ticket.category  && <CategoryBadge  category={ticket.category}   />}
          {ticket.urgency   && <UrgencyBadge   urgency={ticket.urgency}     />}
          {ticket.sentiment && <SentimentBadge sentiment={ticket.sentiment} />}
          <StatusBadge status={ticket.status} />
        </div>

        <div className="bg-gray-50 rounded-lg p-4 mb-5 text-sm text-gray-700 leading-relaxed">
          {ticket.description}
        </div>

        <div className="flex flex-wrap gap-6 text-sm">
          <div>
            <p className="text-xs text-gray-400 mb-1 uppercase tracking-wide">Assigned Team</p>
            <p className="font-medium text-gray-700">{ticket.team || '—'}</p>
          </div>
          <div>
            <p className="text-xs text-gray-400 mb-1 uppercase tracking-wide">SLA Deadline</p>
            <p className="font-medium text-gray-700">
              {ticket.sla_deadline ? format(new Date(ticket.sla_deadline), 'PPp') : '—'}
            </p>
          </div>
          {ticket.resolved_at && (
            <div>
              <p className="text-xs text-gray-400 mb-1 uppercase tracking-wide">Resolved At</p>
              <p className="font-medium text-gray-700">{format(new Date(ticket.resolved_at), 'PPp')}</p>
            </div>
          )}
        </div>
      </div>

      {/* AI Draft Reply */}
      <div className="bg-white rounded-xl shadow-sm border border-blue-100 p-6 mb-4">
        <div className="flex items-center gap-2 mb-3">
          <Bot size={16} className="text-blue-600" />
          <h2 className="font-semibold text-gray-900 text-sm">AI Draft Reply</h2>
          <span className="text-xs bg-blue-50 text-blue-600 px-2 py-0.5 rounded-full">phi3:mini · Ollama</span>
          {replySent && (
            <span className="ml-auto flex items-center gap-1 text-xs text-green-600 font-medium">
              <CheckCircle2 size={13} /> Reply Sent
            </span>
          )}
        </div>

        {replySent ? (
          <div className="bg-green-50 border border-green-200 rounded-lg p-4 text-sm text-green-800 leading-relaxed whitespace-pre-wrap">
            {reply}
          </div>
        ) : (
          <>
            <textarea
              value={reply}
              onChange={(e) => setReply(e.target.value)}
              rows={6}
              placeholder="AI draft will appear here. You can edit it before sending."
              className="w-full text-sm text-gray-700 border border-gray-200 rounded-lg p-3 focus:outline-none focus:ring-2 focus:ring-blue-500 resize-none"
            />
            <div className="flex items-center justify-between mt-3">
              <p className="text-xs text-gray-400">
                Generated by phi3:mini via Ollama. Edit before sending.
              </p>
              <div className="flex items-center gap-2">
                {saveMsg && (
                  <span className={`text-xs font-medium ${saveMsg.includes('fail') ? 'text-red-500' : 'text-green-600'}`}>
                    {saveMsg}
                  </span>
                )}
                <button
                  onClick={saveDraft}
                  disabled={saving || !reply.trim()}
                  className="flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg border border-gray-200 text-gray-600 hover:border-blue-400 hover:text-blue-600 disabled:opacity-50 transition-colors"
                >
                  <Save size={12} />
                  {saving ? 'Saving…' : 'Save Draft'}
                </button>
                <button
                  onClick={sendReply}
                  disabled={sending || !reply.trim()}
                  className="flex items-center gap-1.5 text-xs px-4 py-1.5 rounded-lg bg-blue-600 text-white hover:bg-blue-700 disabled:opacity-50 transition-colors"
                >
                  <Send size={12} />
                  {sending ? 'Sending…' : 'Send Reply'}
                </button>
              </div>
            </div>
          </>
        )}
      </div>

      {/* Actions */}
      <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-6">
        <h2 className="font-semibold text-gray-900 text-sm mb-4">Actions</h2>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-xs text-gray-500 mb-1.5">Update Status</label>
            <div className="flex gap-2 flex-wrap">
              {STATUSES.map((s) => (
                <button
                  key={s}
                  onClick={() => updateStatus(s)}
                  disabled={ticket.status === s}
                  className={`text-xs px-3 py-1.5 rounded-lg border transition-colors ${
                    ticket.status === s
                      ? 'bg-blue-600 text-white border-blue-600'
                      : 'border-gray-200 text-gray-600 hover:border-blue-400 hover:text-blue-600'
                  }`}
                >
                  {s.replace('_', ' ')}
                </button>
              ))}
            </div>
          </div>
          <div>
            <label className="block text-xs text-gray-500 mb-1.5">Override Category</label>
            <select
              value={ticket.category || ''}
              onChange={(e) => overrideCategory(e.target.value)}
              className="w-full text-xs border border-gray-200 rounded-lg px-3 py-1.5 focus:outline-none focus:ring-2 focus:ring-blue-500"
            >
              {CATEGORIES.map((c) => <option key={c}>{c}</option>)}
            </select>
          </div>
        </div>
      </div>
    </div>
  )
}
