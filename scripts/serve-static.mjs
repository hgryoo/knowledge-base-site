#!/usr/bin/env node
// Tiny static HTTP server for the local/LAN deploy. Wraps `serve-handler`
// (a Quartz dep) so we get clean URLs — `/en/methodology/korean-translation`
// resolves to `korean-translation.html` — which python's http.server cannot
// do. Bound on 0.0.0.0:$PORT (default 9090).
import http from "node:http"
import path from "node:path"
import handler from "serve-handler"

const port = parseInt(process.env.PORT || "9090", 10)
const root = path.resolve(process.argv[2] || "public")

const server = http.createServer((req, res) =>
  handler(req, res, {
    public: root,
    cleanUrls: true,
    trailingSlash: false,
    directoryListing: false,
  }),
)

server.listen(port, "0.0.0.0", () => {
  console.log(`serve-static: ${root} on 0.0.0.0:${port}`)
})

for (const sig of ["SIGINT", "SIGTERM"]) {
  process.on(sig, () => server.close(() => process.exit(0)))
}
