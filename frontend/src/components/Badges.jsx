const URGENCY_COLORS = {
  Critical: 'bg-red-100 text-red-700 border border-red-300',
  High: 'bg-orange-100 text-orange-700 border border-orange-300',
  Medium: 'bg-yellow-100 text-yellow-700 border border-yellow-300',
  Low: 'bg-green-100 text-green-700 border border-green-300',
}

const CATEGORY_COLORS = {
  'Technical Issue': 'bg-blue-100 text-blue-700',
  'Billing Query': 'bg-purple-100 text-purple-700',
  'General Inquiry': 'bg-teal-100 text-teal-700',
  'HR/Internal': 'bg-pink-100 text-pink-700',
  Other: 'bg-gray-100 text-gray-600',
}

const STATUS_COLORS = {
  open: 'bg-blue-50 text-blue-600 border border-blue-200',
  in_progress: 'bg-yellow-50 text-yellow-700 border border-yellow-200',
  resolved: 'bg-green-50 text-green-700 border border-green-200',
}

const SENTIMENT_COLORS = {
  positive: 'bg-green-100 text-green-700',
  neutral: 'bg-gray-100 text-gray-600',
  negative: 'bg-red-100 text-red-700',
  mixed: 'bg-orange-100 text-orange-700',
}

function Badge({ label, colorClass }) {
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${colorClass}`}>
      {label}
    </span>
  )
}

export function UrgencyBadge({ urgency }) {
  return <Badge label={urgency} colorClass={URGENCY_COLORS[urgency] || URGENCY_COLORS.Low} />
}

export function CategoryBadge({ category }) {
  return <Badge label={category} colorClass={CATEGORY_COLORS[category] || CATEGORY_COLORS.Other} />
}

export function StatusBadge({ status }) {
  return <Badge label={status.replace('_', ' ')} colorClass={STATUS_COLORS[status] || STATUS_COLORS.open} />
}

export function SentimentBadge({ sentiment }) {
  return <Badge label={sentiment} colorClass={SENTIMENT_COLORS[sentiment] || SENTIMENT_COLORS.neutral} />
}
