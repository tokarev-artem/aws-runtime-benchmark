// Constant request rate against one endpoint.
// k6 run -e BASE_URL=https://... -e ENDPOINT=/api/item -e RATE=50 -e DURATION=2m bench/load.js
import http from "k6/http";
import { check } from "k6";

const BASE = __ENV.BASE_URL;
const ENDPOINT = __ENV.ENDPOINT || "/api/item";
const RATE = Number(__ENV.RATE || 10);

export const options = {
  discardResponseBodies: false,
  summaryTrendStats: ["min", "med", "p(95)", "p(99)", "max"],
  scenarios: {
    steady: {
      executor: "constant-arrival-rate",
      rate: RATE,
      timeUnit: "1s",
      duration: __ENV.DURATION || "2m",
      preAllocatedVUs: Math.max(10, RATE * 2),
      maxVUs: Math.max(50, RATE * 10),
    },
  },
};

export default function () {
  const res = http.get(`${BASE}${ENDPOINT}`, { tags: { endpoint: ENDPOINT } });
  check(res, { "status 200": (r) => r.status === 200 });
}

export function handleSummary(data) {
  const d = data.metrics.http_req_duration.values;
  const row = {
    target: BASE, endpoint: ENDPOINT, rate: RATE,
    requests: data.metrics.http_reqs.values.count,
    failed: data.metrics.http_req_failed.values.rate,
    min: d.min, p50: d.med, p95: d["p(95)"], p99: d["p(99)"], max: d.max,
    dropped: data.metrics.dropped_iterations ? data.metrics.dropped_iterations.values.count : 0,
  };
  return {
    stdout: JSON.stringify(row) + "\n",
    [`results/load-${__ENV.LABEL || "run"}-${ENDPOINT.replace(/\W+/g, "_")}-${RATE}rps.json`]: JSON.stringify(row, null, 2),
  };
}
