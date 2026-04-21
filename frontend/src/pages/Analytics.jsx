import { useEffect, useState } from 'react'
import { api } from '../api/tickets'
import CategoryDonut from '../components/charts/CategoryDonut'
import DailyVolumeBar from '../components/charts/DailyVolumeBar'
import ResolutionTrend from '../components/charts/ResolutionTrend'

const POWERBI_URL = import.meta.env.VITE_POWERBI_URL || ''

export default function Analytics() {
  const [categories, setCategories] = useState([])
  const [daily, setDaily] = useState([])
  const [resolution, setResolution] = useState([])
  const [teams, setTeams] = useState([])

  useEffect(() => {
    api.analytics.categories().then(setCategories).catch(() => {})
    api.analytics.daily().then(setDaily).catch(() => {})
    api.analytics.resolution().then(setResolution).catch(() => {})
    api.analytics.teams().then(setTeams).catch(() => {})
  }, [])

  return (
    <div>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Analytics</h1>
        <p className="text-sm text-gray-500 mt-0.5">Ticket distribution, volume trends, and resolution performance</p>
      </div>

      <div className="grid grid-cols-3 gap-4 mb-4">
        <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-5">
          <h3 className="text-sm font-semibold text-gray-900 mb-4">Category Distribution</h3>
          <CategoryDonut data={categories} />
        </div>

        <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-5">
          <h3 className="text-sm font-semibold text-gray-900 mb-4">Daily Volume (Last 7 Days)</h3>
          <DailyVolumeBar data={daily} />
        </div>

        <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-5">
          <h3 className="text-sm font-semibold text-gray-900 mb-4">Avg. Resolution Time</h3>
          <ResolutionTrend data={resolution} />
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4 mb-4">
        <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-5">
          <h3 className="text-sm font-semibold text-gray-900 mb-3">Team Workload (Open Tickets)</h3>
          {teams.length ? (
            <div className="space-y-3">
              {teams.map((t) => (
                <div key={t.team}>
                  <div className="flex justify-between text-xs text-gray-600 mb-1">
                    <span>{t.team}</span>
                    <span className="font-medium">{t.count}</span>
                  </div>
                  <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
                    <div
                      className="h-full bg-blue-500 rounded-full"
                      style={{ width: `${Math.min(100, (t.count / (Math.max(...teams.map(x => x.count)) || 1)) * 100)}%` }}
                    />
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-sm text-gray-400">No open tickets</p>
          )}
        </div>

        {POWERBI_URL ? (
          <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-5">
            <h3 className="text-sm font-semibold text-gray-900 mb-3">
              Power BI Report
              <span className="ml-2 text-xs bg-yellow-50 text-yellow-700 px-2 py-0.5 rounded-full border border-yellow-200">
                Microsoft Azure
              </span>
            </h3>
            <iframe
              title="Power BI Report"
              src={POWERBI_URL}
              className="w-full h-64 rounded-lg border border-gray-100"
              allowFullScreen
            />
          </div>
        ) : (
          <div className="bg-white rounded-xl shadow-sm border border-dashed border-gray-200 p-5 flex flex-col items-center justify-center text-center">
            <p className="text-sm font-medium text-gray-500 mb-1">Power BI Report</p>
            <p className="text-xs text-gray-400 mb-3">
              Set <code className="bg-gray-100 px-1 py-0.5 rounded">VITE_POWERBI_URL</code> in your .env to embed your Power BI Publish-to-Web report here.
            </p>
            <a
              href="https://app.powerbi.com"
              target="_blank"
              rel="noreferrer"
              className="text-xs text-blue-600 hover:underline"
            >
              Open Power BI →
            </a>
          </div>
        )}
      </div>
    </div>
  )
}
