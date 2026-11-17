# One image for both Lambda and ECS Fargate (linux/arm64).
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-fund --no-audit
COPY . .
ENV STANDALONE=1 NEXT_TELEMETRY_DISABLED=1
RUN npm run build

FROM node:22-alpine
# Lambda Web Adapter: a Lambda extension that turns invoke events into HTTP requests
# to the web server below. Outside Lambda (on ECS) it is never started.
COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:0.9.1 /lambda-adapter /opt/extensions/lambda-adapter
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 HOSTNAME=0.0.0.0 \
    AWS_LWA_READINESS_CHECK_PATH=/api/health
COPY --from=build /app/.next/standalone ./
COPY --from=build /app/.next/static ./.next/static
COPY --from=build /app/public ./public
# Lambda's file system is read-only except /tmp; point the Next.js cache there.
RUN rm -rf .next/cache && ln -s /tmp/next-cache .next/cache
USER node
EXPOSE 3000
CMD ["node", "server.js"]
