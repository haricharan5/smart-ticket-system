import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Send, Loader2 } from 'lucide-react'
import { api } from '../api/tickets'

export default function SubmitTicket() {
  const navigate = useNavigate()
  const [form, setForm] = useState({ title: '', description: '', submitter_email: '' })
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState(null)

  const handleSubmit = async (e) => {
    e.preventDefault()
    setLoading(true)
    setError(null)
    try {
      const ticket = await api.tickets.create(form)
      navigate(`/tickets/${ticket.id}`)
    } catch (err) {
      setError('Failed to submit ticket. Please try again.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="max-w-2xl">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Submit New Ticket</h1>
        <p className="text-sm text-gray-500 mt-0.5">
          Our AI will classify and route your ticket automatically.
        </p>
      </div>

      <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-6">
        <form onSubmit={handleSubmit} className="space-y-5">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1.5">
              Your Email <span className="text-red-500">*</span>
            </label>
            <input
              type="email"
              required
              value={form.submitter_email}
              onChange={(e) => setForm({ ...form, submitter_email: e.target.value })}
              placeholder="you@company.com"
              className="w-full border border-gray-200 rounded-lg px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1.5">
              Issue Title <span className="text-red-500">*</span>
            </label>
            <input
              type="text"
              required
              value={form.title}
              onChange={(e) => setForm({ ...form, title: e.target.value })}
              placeholder="Brief description of the issue"
              className="w-full border border-gray-200 rounded-lg px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1.5">
              Description <span className="text-red-500">*</span>
            </label>
            <textarea
              required
              rows={6}
              value={form.description}
              onChange={(e) => setForm({ ...form, description: e.target.value })}
              placeholder="Describe your issue in detail — the more context, the faster we can help."
              className="w-full border border-gray-200 rounded-lg px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 resize-none"
            />
          </div>

          {error && (
            <p className="text-sm text-red-600 bg-red-50 border border-red-200 rounded-lg px-4 py-2.5">
              {error}
            </p>
          )}

          <button
            type="submit"
            disabled={loading}
            className="w-full flex items-center justify-center gap-2 bg-blue-600 text-white font-medium py-2.5 rounded-lg hover:bg-blue-700 disabled:opacity-60 transition-colors text-sm"
          >
            {loading ? (
              <>
                <Loader2 size={16} className="animate-spin" />
                Classifying with AI...
              </>
            ) : (
              <>
                <Send size={15} />
                Submit Ticket
              </>
            )}
          </button>
          {loading && (
            <p className="text-center text-xs text-gray-400">
              Azure AI is classifying your ticket — this takes ~3 seconds
            </p>
          )}
        </form>
      </div>
    </div>
  )
}
