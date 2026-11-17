// Entry file for Lambda Web Functions. Lambda tells the server where to listen in
// AWS_LAMBDA_HTTP_ENDPOINT ("host:port"); Next.js standalone reads HOSTNAME and PORT.
const [host, port] = (process.env.AWS_LAMBDA_HTTP_ENDPOINT || "localhost:3000").split(":");
process.env.HOSTNAME = host;
process.env.PORT = port;
require("./server.js");
