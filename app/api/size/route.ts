export const dynamic = "force-dynamic";

// Returns ?mb= megabytes, to find each runtime's real response size limit.
export function GET(req: Request) {
  const mb = Math.min(Number(new URL(req.url).searchParams.get("mb")) || 1, 50);
  return new Response("x".repeat(Math.round(mb * 1024 * 1024)), {
    headers: { "content-type": "text/plain" },
  });
}
