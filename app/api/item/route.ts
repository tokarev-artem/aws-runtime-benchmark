import { runtimeInfo } from "@/lib/runtime";
import { getGreeting } from "@/lib/db";

export const dynamic = "force-dynamic";

// One DynamoDB GetItem: a typical API call.
export async function GET() {
  const info = runtimeInfo();
  try {
    return Response.json({ ...info, ...(await getGreeting()) });
  } catch (e) {
    return Response.json({ ...info, error: (e as Error).name }, { status: 500 });
  }
}
