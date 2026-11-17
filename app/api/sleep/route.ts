export const dynamic = "force-dynamic";

// Waits ?s= seconds, to find each runtime's real request timeout.
export async function GET(req: Request) {
  const s = Math.min(Number(new URL(req.url).searchParams.get("s")) || 1, 900);
  await new Promise((r) => setTimeout(r, s * 1000));
  return Response.json({ sleptSeconds: s });
}
