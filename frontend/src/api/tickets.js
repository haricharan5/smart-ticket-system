const BASE = import.meta.env.VITE_API_URL || ''

function getToken() {
  return localStorage.getItem('auth_token')
}

async function req(path, options = {}) {
  const token = getToken()
  const res = await fetch(`${BASE}${path}`, {
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...options,
  })
  if (res.status === 401) {
    // Token expired — force re-login
    localStorage.removeItem('auth_token')
    localStorage.removeItem('auth_user')
    window.location.href = '/login'
    throw new Error('Session expired')
  }
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`)
  return res.json()
}

export const api = {
  tickets: {
    list: (params = {}) => {
      const qs = new URLSearchParams(
        Object.fromEntries(Object.entries(params).filter(([, v]) => v != null))
      ).toString()
      return req(`/api/tickets${qs ? `?${qs}` : ''}`)
    },
    get: (id) => req(`/api/tickets/${id}`),
    create: (body) => req('/api/tickets', { method: 'POST', body: JSON.stringify(body) }),
    updateStatus: (id, status) =>
      req(`/api/tickets/${id}/status`, { method: 'PATCH', body: JSON.stringify({ status }) }),
    overrideCategory: (id, category) =>
      req(`/api/tickets/${id}/category`, { method: 'PATCH', body: JSON.stringify({ category }) }),
    updateReply: (id, reply) =>
      req(`/api/tickets/${id}/reply`, { method: 'PATCH', body: JSON.stringify({ reply }) }),
  },
  alerts: {
    sla: () => req('/api/alerts/sla'),
    outage: () => req('/api/alerts/outage'),
    resolveOutage: (id) => req(`/api/alerts/outage/${id}/resolve`, { method: 'PATCH' }),
  },
  analytics: {
    summary: () => req('/api/analytics/summary'),
    categories: () => req('/api/analytics/categories'),
    daily: () => req('/api/analytics/daily'),
    resolution: () => req('/api/analytics/resolution'),
    sentiment: () => req('/api/analytics/sentiment'),
    teams: () => req('/api/analytics/teams'),
  },
}
