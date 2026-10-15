import type { Metadata } from "next";
import "./foundation.css";
import "./project.css";

export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL ?? "https://stepwell-one.vercel.app"),
  title: "Stepwell · first-loss cover for Morpho vaults on Arc",
  description:
    "When a vault on Arc loses money, underwriters take the hit before depositors do. Cover is paid from depositors' interest, and any app can add it.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" data-mood="cream" data-accent="well" suppressHydrationWarning>
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link
          href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400..800&family=Geist+Mono:wght@400;500&family=Eczar:wght@600&display=swap"
          rel="stylesheet"
        />
        <script dangerouslySetInnerHTML={{ __html: "document.documentElement.classList.add('js')" }} />
      </head>
      <body>{children}</body>
    </html>
  );
}
