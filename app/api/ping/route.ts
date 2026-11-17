import { runtimeInfo } from "@/lib/runtime";

export const dynamic = "force-dynamic";

// No I/O: measures the runtime's own request overhead.
export function GET() {
  return Response.json(runtimeInfo());
}
