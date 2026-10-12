#!/usr/bin/env python3
"""Build results/comparison.md + results/waterfall.png from measure.py output and netlogs."""
import collections, json, statistics, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "results"
MODES = [m for m in ["direct", "proxy-h1", "proxy-h2"] if (RES / f"summary-{m}.json").exists()]
LABEL = {"direct": "(a) direct to origin", "proxy-h1": "(b) via TLS-inspecting proxy, h1 only",
         "proxy-h2": "(c) via proxy with HTTP/2 enabled (fix)"}
# Netlog event types worth looking at for this problem
KEY_EVENTS = ["SOCKET_POOL_STALLED_MAX_SOCKETS_PER_GROUP", "SOCKET_POOL_STALLED_MAX_SOCKETS",
              "SOCKET_POOL_REUSED_AN_EXISTING_SOCKET", "RESOURCE_SCHEDULER_REQUEST_STARTED",
              "HTTP2_SESSION_INITIALIZED", "HTTP2_SESSION_POOL_FOUND_EXISTING_SESSION",
              "HTTP2_SESSION_STALLED_MAX_STREAMS", "HTTP_TRANSACTION_SEND_TUNNEL_HEADERS"]


def netlog_facts(path, host="localhost:8443"):
    """Count key events, scoped to netlog sources related to the demo host (Chrome's own background
    traffic to google.com etc. is excluded). A source is related if any of its params mention the host,
    or if a related source points at it via params.source_dependency (URL_REQUEST -> stream job -> socket)."""
    d = json.load(open(path))
    names = {v: k for k, v in d["constants"]["logEventTypes"].items()}
    tagged, deps = set(), collections.defaultdict(set)
    for e in d["events"]:
        p = e.get("params") or {}
        if host in json.dumps(p): tagged.add(e["source"]["id"])
        sd = p.get("source_dependency")
        if isinstance(sd, dict): deps[e["source"]["id"]].add(sd["id"])
    todo = list(tagged)
    while todo:
        for t in deps[todo.pop()]:
            if t not in tagged: tagged.add(t); todo.append(t)
    ev = collections.Counter()
    next_proto, req_proto, maxstreams, proxy = collections.Counter(), collections.Counter(), set(), set()
    for e in d["events"]:
        if e["source"]["id"] not in tagged: continue
        n = names.get(e["type"]); p = e.get("params") or {}
        ev[n] += 1
        if n == "SSL_CONNECT" and "next_proto" in p: next_proto[p["next_proto"]] += 1
        if n == "HTTP_STREAM_REQUEST_PROTO": req_proto[p.get("proto")] += 1
        if n == "HTTP2_SESSION_STALLED_MAX_STREAMS": maxstreams.add(p.get("max_concurrent_streams"))
        if n == "HTTP_STREAM_JOB_CONTROLLER_PROXY_SERVER_RESOLVED": proxy.add(p.get("proxy_chain"))
    return {"events": {k: ev.get(k, 0) for k in KEY_EVENTS}, "ssl_next_proto (TLS sockets)": dict(next_proto),
            "stream_request_proto": dict(req_proto), "h2_max_concurrent_streams": sorted(maxstreams),
            "proxy_chain": sorted(proxy)}


def main():
    rows, facts = {}, {}
    for m in MODES:
        runs = json.load(open(RES / f"summary-{m}.json"))
        rows[m] = runs
        facts[m] = netlog_facts(ROOT / runs[0]["netlog"])
    md = ["# Measured comparison (headless Chrome, %s)\n" % ", ".join(MODES),
          "Values per run; page_done = all scripts, images and fetch() calls finished. "
          "Stalled = DevTools 'Stalled'; queue+stall = DevTools 'Queueing' + 'Stalled' (time before the request was sent).\n",
          "| mode | run | page done (ms) | protocol | connection IDs | issuer | stalled sum / median / max (ms) | queue+stall sum / median / max (ms) |",
          "|---|---|---|---|---|---|---|---|"]
    for m in MODES:
        for r in rows[m]:
            md.append(f"| {LABEL[m]} | {r['run']} | {r['page_done_ms']:.0f} | {','.join(r['protocols'])} | {r['distinct_connection_ids']} | "
                      f"{','.join(r['cert_issuer'])} | {r['stalled_sum_ms']} / {r['stalled_median_ms']} / {r['stalled_max_ms']} | "
                      f"{r['queue+stall_sum_ms']} / {r['queue+stall_median_ms']} / {r['queue+stall_max_ms']} |")
    md += ["", "Median page-done across runs: " + ", ".join(
        f"{m} = {statistics.median(r['page_done_ms'] for r in rows[m]):.0f} ms" for m in MODES), "",
        "## Netlog evidence (run 1 of each mode; scoped to localhost:8443 sources; counts include BEGIN/END pairs where applicable)\n",
        "| netlog fact | " + " | ".join(MODES) + " |", "|---|" + "---|" * len(MODES)]
    for k in ["ssl_next_proto (TLS sockets)", "stream_request_proto", "proxy_chain", "h2_max_concurrent_streams"]:
        md.append(f"| {k} | " + " | ".join(f"`{json.dumps(facts[m][k])}`" for m in MODES) + " |")
    for k in KEY_EVENTS:
        md.append(f"| {k} | " + " | ".join(str(facts[m]['events'][k]) for m in MODES) + " |")
    (RES / "comparison.md").write_text("\n".join(md) + "\n")
    (RES / "netlog-facts.json").write_text(json.dumps(facts, indent=1))
    print("\n".join(md))
    chart()


def chart():
    import matplotlib; matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(len(MODES), 1, figsize=(11, 3.4 * len(MODES)), sharex=True)
    for ax, m in zip(axes if len(MODES) > 1 else [axes], MODES):
        run = json.load(open(RES / f"requests-{m}-run1.json"))
        reqs = sorted(run["requests"], key=lambda r: r["start_ms"])
        for i, r in enumerate(reqs):
            ax.barh(i, r["blocked_ms"], left=r["start_ms"], color="tab:orange", height=1.0, linewidth=0)
            rest = (r["total_ms"] or r["blocked_ms"]) - r["blocked_ms"]
            ax.barh(i, rest, left=r["start_ms"] + r["blocked_ms"], color="tab:blue", height=1.0, linewidth=0)
        s = json.load(open(RES / f"summary-{m}.json"))[0]
        ax.set_title(f"{LABEL[m]}: {','.join(s['protocols'])}, {s['distinct_connection_ids']} connection(s), "
                     f"page done {s['page_done_ms']:.0f} ms", fontsize=10)
        ax.set_ylabel("request #"); ax.invert_yaxis()
    axes[-1].set_xlabel("ms since first request   (orange = Queueing+Stalled, blue = request/response)")
    fig.tight_layout(); fig.savefig(RES / "waterfall.png", dpi=110)
    print("wrote", RES / "waterfall.png")


if __name__ == "__main__":
    main()
