import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import { Inter } from "next/font/google";

import { SITE } from "@/components/landing/content";

import "./globals.css";

const inter = Inter({
  variable: "--font-inter",
  subsets: ["latin"],
  display: "swap",
});

export const metadata: Metadata = {
  metadataBase: new URL(SITE.url),
  title: SITE.title,
  description: SITE.description,
  openGraph: {
    title: SITE.title,
    description: SITE.description,
    url: SITE.url,
    siteName: SITE.brand,
    type: "website",
  },
  icons: { icon: "/icon.svg" },
};

/** The browser chrome on a phone takes the page's own ground, `--color-bg` in globals.css. */
export const viewport: Viewport = { themeColor: "#08090b" };

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" className={`${inter.variable} h-full antialiased`}>
      <body className="min-h-full flex flex-col">
        <a
          href="#main"
          className="sr-only focus:not-sr-only focus:fixed focus:top-3 focus:left-3 focus:z-50 focus:rounded-ctl focus:bg-ink-0 focus:px-3 focus:py-2 focus:text-sec focus:font-medium focus:text-bg focus:no-underline"
        >
          Skip to content
        </a>
        {children}
      </body>
    </html>
  );
}
