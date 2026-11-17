export const dynamic = "force-dynamic";

// Used by the Lambda Web Adapter readiness check and the ALB health check.
// It does not touch runtimeInfo(), so probes never hide a cold start.
export function GET() {
  return new Response("ok");
}
