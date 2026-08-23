import type { NextConfig } from "next";
import path from "node:path";

const nextConfig: NextConfig = {
  // Pin the workspace root to this app — the parent Scanima repo also has a
  // package-lock.json one level up, which Turbopack would otherwise guess at.
  turbopack: {
    root: path.join(__dirname),
  },
};

export default nextConfig;
