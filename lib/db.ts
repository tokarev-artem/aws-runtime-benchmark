import { DynamoDBClient, GetItemCommand } from "@aws-sdk/client-dynamodb";

// Amplify reserves the AWS_ prefix for environment variables, so the app reads APP_REGION first.
const region = process.env.APP_REGION ?? process.env.AWS_REGION ?? "eu-central-1";
const table = process.env.TABLE_NAME ?? "runtime-benchmark";
const client = new DynamoDBClient({ region });

export async function getGreeting() {
  const started = performance.now();
  const out = await client.send(
    new GetItemCommand({ TableName: table, Key: { pk: { S: "greeting" } } })
  );
  return {
    message: out.Item?.message?.S ?? "(item not found)",
    dbMs: Math.round((performance.now() - started) * 10) / 10,
  };
}
