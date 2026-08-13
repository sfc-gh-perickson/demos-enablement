import './globals.css';
import { Inter } from 'next/font/google';

const inter = Inter({ subsets: ['latin'] });

export const metadata = {
  title: 'Fraud Investigation Portal',
  description: 'Proactive fraud detection and investigation dashboard',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="dark">
      <body className={`${inter.className} min-h-screen bg-sf-bg`}>
        <nav className="sticky top-0 z-50 border-b border-sf-border px-6 py-4 bg-sf-nav">
          <div className="flex items-center justify-between max-w-7xl mx-auto">
            <h1 className="text-xl font-bold text-white">
              Fraud Investigation Portal
            </h1>
            <span className="text-sm text-sf-text-muted">Powered by Snowflake Cortex</span>
          </div>
        </nav>
        <main className="max-w-7xl mx-auto px-6 py-8">{children}</main>
      </body>
    </html>
  );
}
