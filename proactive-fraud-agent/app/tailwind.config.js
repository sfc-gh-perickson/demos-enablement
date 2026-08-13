/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./src/**/*.{js,ts,jsx,tsx,mdx}'],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        fraud: { high: '#ef4444', medium: '#f59e0b', low: '#22c55e' },
        sf: {
          bg: 'var(--sf-bg)',
          nav: 'var(--sf-nav)',
          card: 'var(--sf-card)',
          'card-deep': 'var(--sf-card-deep)',
          hover: 'var(--sf-hover)',
          border: 'var(--sf-border)',
          accent: 'var(--sf-accent)',
          'accent-hover': 'var(--sf-accent-hover)',
          'accent-muted': 'var(--sf-accent-muted)',
          text: 'var(--sf-text)',
          'text-muted': 'var(--sf-text-muted)',
          'text-dim': 'var(--sf-text-dim)',
        },
      },
    },
  },
  plugins: [require('@tailwindcss/typography')],
};
