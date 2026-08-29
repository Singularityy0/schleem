import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL ?? 'http://localhost:3000'),
  title: 'Schmeckles · Five-minute capped calls',
  description: 'Jump-aware, fully reserved five-minute MON/USD capped calls on Monad Testnet.',
  openGraph: {
    title: 'Schmeckles · Five-minute capped calls',
    description: 'Five-minute MON upside. Risk capped.',
    images: [{ url: '/og.png', width: 1200, height: 630, alt: 'Schmeckles capped-call payoff' }],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Schmeckles · Five-minute capped calls',
    description: 'Five-minute MON upside. Risk capped.',
    images: ['/og.png'],
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className="dark">
      <body>{children}</body>
    </html>
  );
}
