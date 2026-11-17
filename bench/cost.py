#!/usr/bin/env python3
"""Monthly cost of each runtime at several traffic levels (eu-central-1 on-demand prices).

usage: bench/cost.py [--lambda-ms 120] [--amplify-ms 150] [--kb 5]
Durations are the average billed duration per request (Lambda: CloudWatch "Duration";
Amplify: approximated from server-side latency). Free tiers are ignored.
"""
import argparse

HOURS = 730
P = {  # USD, AWS Price List API, eu-central-1
    "fargate_arm_vcpu_h": 0.03725, "fargate_arm_gb_h": 0.00409,
    "alb_h": 0.027, "alb_lcu_h": 0.008, "ipv4_h": 0.005,
    "lambda_arm_gb_s": 0.0000133334, "lambda_req": 0.20 / 1e6,
    "amplify_gb_s": 0.20 / 3600, "amplify_req": 0.30 / 1e6, "amplify_gb_out": 0.15,
    "data_out_gb": 0.09,  # EC2/Lambda internet egress, first 10 TB (after 100 GB free)
}

ap = argparse.ArgumentParser()
ap.add_argument("--lambda-ms", type=float, default=120)
ap.add_argument("--amplify-ms", type=float, default=150)
ap.add_argument("--kb", type=float, default=5, help="average response size")
ap.add_argument("--tasks", type=int, default=1, help="Fargate tasks (0.5 vCPU, 1 GB)")
a = ap.parse_args()

def ecs(req):
    # A 0.5 vCPU task served ~X req/s in the load test; add tasks as traffic grows.
    rps = req / (HOURS * 3600)
    tasks = max(a.tasks, -(-rps // 50))  # assume ~50 req/s per task for this app
    fargate = tasks * (0.5 * P["fargate_arm_vcpu_h"] + 1 * P["fargate_arm_gb_h"]) * HOURS
    lcu = max(1, rps / 25) * P["alb_lcu_h"] * HOURS  # 25 new connections/s per LCU (rough)
    ipv4 = (3 + tasks) * P["ipv4_h"] * HOURS          # ALB has one public IP per AZ (3)
    egress = req * a.kb / 1e6 * P["data_out_gb"]
    return fargate + P["alb_h"] * HOURS + lcu + ipv4 + egress, int(tasks)

def lam(req):
    return req * (P["lambda_req"] + a.lambda_ms / 1000 * 1 * P["lambda_arm_gb_s"]) + req * a.kb / 1e6 * P["data_out_gb"]

def amp(req):
    return req * (P["amplify_req"] + a.amplify_ms / 1000 * 1 * P["amplify_gb_s"]) + req * a.kb / 1e6 * P["amplify_gb_out"]

print(f"{'requests/month':>15} {'Lambda':>10} {'Amplify':>10} {'ECS+ALB':>10}  tasks")
for req in (10_000, 1_000_000, 10_000_000, 100_000_000):
    e, t = ecs(req)
    print(f"{req:>15,} {lam(req):>10.2f} {amp(req):>10.2f} {e:>10.2f}  {t}")
