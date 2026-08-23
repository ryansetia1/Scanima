import type { NextConfig } from "next";
import path from "node:path";

const nextConfig: NextConfig = {
  // Pin the workspace root to this app — the parent Scanima repo also has a
  // package-lock.json one level up, which Turbopack would otherwise guess at.
  turbopack: {
    root: path.join(__dirname),
  },
  experimental: {
    // Every route here is dynamic (searchParams + no-store fetches), and
    // Next 15+ defaults dynamic client-cache staleTime to 0s -- so leaving
    // Queue and coming straight back always re-fetched and re-showed
    // loading.tsx even though nothing changed. 30s lets a quick tab switch
    // reuse the cached RSC payload; RealtimeRefresh's router.refresh() still
    // forces a live refetch on the page you're actively viewing when a case
    // actually changes, so this only affects the "nothing changed" case.
    staleTimes: {
      dynamic: 30,
    },
  },
};

export default nextConfig;
