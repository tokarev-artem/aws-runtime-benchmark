// Process-level state. A "cold" request is the first one this process serves,
// so it includes module loading and SDK client creation.
const processStart = Date.now();
let requests = 0;

export function runtimeInfo() {
  requests += 1;
  return {
    runtime: process.env.RUNTIME_NAME ?? "local",
    cold: requests === 1,
    requestsServed: requests,
    processUptimeMs: Date.now() - processStart,
    arch: process.arch,
    node: process.version,
    memoryMb: Number(process.env.AWS_LAMBDA_FUNCTION_MEMORY_SIZE) || undefined,
  };
}
