import type { Metadata } from "next";
import { Space_Grotesk, Fira_Sans, Fira_Code } from "next/font/google";
import "./globals.css";

const spaceGrotesk = Space_Grotesk({
  variable: "--font-space-grotesk",
  subsets: ["latin"],
  weight: ["500", "600", "700"],
});

const firaSans = Fira_Sans({
  variable: "--font-fira-sans",
  subsets: ["latin"],
  weight: ["400", "500", "600"],
});

const firaCode = Fira_Code({
  variable: "--font-fira-code",
  subsets: ["latin"],
  weight: ["400", "500"],
});

export const metadata: Metadata = {
  title: "Scanima Control Deck",
  description: "Staff moderation console for the Scanima Atlas gallery",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className={`${spaceGrotesk.variable} ${firaSans.variable} ${firaCode.variable} h-full`}
    >
      <body className="min-h-full bg-deck-bg text-deck-text antialiased font-body">
        {children}
      </body>
    </html>
  );
}
