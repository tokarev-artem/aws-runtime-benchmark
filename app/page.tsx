import { runtimeInfo } from "@/lib/runtime";
import { getGreeting } from "@/lib/db";

// Render on every request, so each runtime does real server work.
export const dynamic = "force-dynamic";

export default async function Home() {
  const started = performance.now();
  const info = runtimeInfo();
  let greeting: { message: string; dbMs: number } | { error: string };
  try {
    greeting = await getGreeting();
  } catch (e) {
    greeting = { error: (e as Error).name + ": " + (e as Error).message };
  }
  const renderMs = Math.round((performance.now() - started) * 10) / 10;

  return (
    <main>
      <h1>Hello from {info.runtime}</h1>
      <p>Server-rendered at {new Date().toISOString()}</p>
      <pre data-testid="info">{JSON.stringify({ ...info, greeting, renderMs }, null, 2)}</pre>
    </main>
  );
}
