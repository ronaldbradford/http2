# Measured comparison (headless Chrome, direct, proxy-h1, proxy-h2)

Values per run; page_done = all scripts, images and fetch() calls finished. Stalled = DevTools 'Stalled'; queue+stall = DevTools 'Queueing' + 'Stalled' (time before the request was sent).

| mode | run | page done (ms) | protocol | connection IDs | issuer | stalled sum / median / max (ms) | queue+stall sum / median / max (ms) |
|---|---|---|---|---|---|---|---|
| (a) direct to origin | 1 | 480 | h2 | 1 | H2 Demo Origin CA | 3462 / 21.2 / 32 | 7430 / 46.3 / 53 |
| (a) direct to origin | 2 | 493 | h2 | 1 | H2 Demo Origin CA | 4644 / 27.2 / 44 | 9732 / 60.0 / 68 |
| (a) direct to origin | 3 | 491 | h2 | 1 | H2 Demo Origin CA | 4553 / 26.8 / 41 | 9050 / 55.4 / 62 |
| (b) via TLS-inspecting proxy, h1 only | 1 | 7374 | http/1.1 | 6 | mitmproxy | 326364 / 1642.9 / 5296 | 605110 / 3547.9 / 7138 |
| (b) via TLS-inspecting proxy, h1 only | 2 | 7362 | http/1.1 | 6 | mitmproxy | 325939 / 1649.7 / 5301 | 605375 / 3549.0 / 7133 |
| (b) via TLS-inspecting proxy, h1 only | 3 | 7374 | http/1.1 | 6 | mitmproxy | 325717 / 1643.0 / 5290 | 604699 / 3551.7 / 7131 |
| (c) via proxy with HTTP/2 enabled (fix) | 1 | 846 | h2 | 1 | mitmproxy | 20440 / 37.5 / 363 | 25574 / 63.0 / 406 |
| (c) via proxy with HTTP/2 enabled (fix) | 2 | 835 | h2 | 1 | mitmproxy | 21621 / 45.3 / 377 | 27605 / 72.6 / 422 |
| (c) via proxy with HTTP/2 enabled (fix) | 3 | 843 | h2 | 1 | mitmproxy | 21385 / 46.3 / 363 | 27554 / 74.7 / 412 |

Median page-done across runs: direct = 491 ms, proxy-h1 = 7374 ms, proxy-h2 = 843 ms

## Netlog evidence (run 1 of each mode; scoped to localhost:8443 sources; counts include BEGIN/END pairs where applicable)

| netlog fact | direct | proxy-h1 | proxy-h2 |
|---|---|---|---|
| ssl_next_proto (TLS sockets) | `{"h2": 1}` | `{"http/1.1": 6}` | `{"h2": 1}` |
| stream_request_proto | `{"h2": 1}` | `{"http/1.1": 171}` | `{"h2": 1}` |
| proxy_chain | `["[direct://]"]` | `["[127.0.0.1:8080]"]` | `["[127.0.0.1:8081]"]` |
| h2_max_concurrent_streams | `[]` | `[]` | `[100]` |
| SOCKET_POOL_STALLED_MAX_SOCKETS_PER_GROUP | 0 | 120 | 0 |
| SOCKET_POOL_STALLED_MAX_SOCKETS | 0 | 0 | 0 |
| SOCKET_POOL_REUSED_AN_EXISTING_SOCKET | 0 | 165 | 0 |
| RESOURCE_SCHEDULER_REQUEST_STARTED | 0 | 104 | 0 |
| HTTP2_SESSION_INITIALIZED | 1 | 0 | 1 |
| HTTP2_SESSION_POOL_FOUND_EXISTING_SESSION | 170 | 0 | 170 |
| HTTP2_SESSION_STALLED_MAX_STREAMS | 0 | 0 | 87 |
| HTTP_TRANSACTION_SEND_TUNNEL_HEADERS | 0 | 6 | 1 |
