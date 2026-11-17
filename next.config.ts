import type { NextConfig } from "next";

// The Docker image (Lambda and ECS) uses the standalone server.
// Amplify Hosting builds the app its own way, so it gets the default output.
const config: NextConfig = {
  output: process.env.STANDALONE ? "standalone" : undefined,
  poweredByHeader: false,
};

export default config;
