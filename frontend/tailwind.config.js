/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        navy: { 800: '#1e2a4a', 900: '#141e35' },
      },
    },
  },
  plugins: [],
}
