const http = require("node:http");

http.createServer((request, response) => {
  const port = request.url.startsWith("/api/") ? 3002 : 8766;
  const proxy = http.request(
    { hostname: "127.0.0.1", port, path: request.url, method: request.method, headers: request.headers },
    upstream => {
      response.writeHead(upstream.statusCode, upstream.headers);
      upstream.pipe(response);
    },
  );
  proxy.on("error", error => {
    response.writeHead(502, { "Content-Type": "text/plain" });
    response.end(error.message);
  });
  request.pipe(proxy);
}).listen(8765, "127.0.0.1", () => console.log("Customer preview proxy listening on port 8765"));
