import { createHash } from "node:crypto";
import { runtimeInfo } from "@/lib/runtime";

export const dynamic = "force-dynamic";

// Fixed CPU work (chained SHA-256), so differences come from the CPU you get.
export function GET(req: Request) {
  const rounds = Math.min(Number(new URL(req.url).searchParams.get("rounds")) || 50000, 500000);
  const started = performance.now();
  let h = "seed";
  for (let i = 0; i < rounds; i++) h = createHash("sha256").update(h).digest("hex");
  const cpuMs = Math.round((performance.now() - started) * 10) / 10;
  return Response.json({ ...runtimeInfo(), rounds, cpuMs, hash: h.slice(0, 12) });
}
