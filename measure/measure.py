#!/usr/bin/env python3
"""Load the demo page in headless Chrome for one mode, capture a netlog + per-request CDP timing.

usage: measure.py MODE [--runs N] [--out results/]
  MODE: direct     -> https://localhost:8443 straight to origin (h2)
        proxy-h1   -> via mitmproxy on :8080 (client side http/1.1 only)
        proxy-h2   -> via mitmproxy on :8081 (http2 enabled = the fix)
"""
import argparse, base64, hashlib, json, os, shutil, statistics, subprocess, sys, time
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent
URL = os.environ.get("DEMO_URL", "https://localhost:8443/")
PROXIES = {"direct": None, "proxy-h1": "http://127.0.0.1:8080", "proxy-h2": "http://127.0.0.1:8081"}


def spki_hash(pem):
    """base64(sha256(SPKI)) for --ignore-certificate-errors-spki-list."""
    pub = subprocess.run(["openssl", "x509", "-in", pem, "-pubkey", "-noout"], capture_output=True, check=True).stdout
    der = subprocess.run(["openssl", "pkey", "-pubin", "-outform", "der"], input=pub, capture_output=True, check=True).stdout
    return base64.b64encode(hashlib.sha256(der).digest()).decode()


def chrome_path():
    for c in [os.environ.get("CHROME"), "google-chrome", "google-chrome-stable", "chromium", "chromium-browser"]:
        if c and shutil.which(c):
            return shutil.which(c)
    return None  # fall back to Playwright's bundled chromium


def one_run(p, mode, netlog_path):
    # Trust the two demo CAs via SPKI pinning (no global trust changes).
    # mitmproxy signs its forged leaf certs with its CA key, so the CA SPKI matches the leaf.
    spkis = [spki_hash(str(ROOT / "certs/origin.pem")), spki_hash(str(ROOT / "certs/mitmproxy/mitmproxy-ca-cert.pem"))]
    args = [f"--log-net-log={netlog_path}", "--net-log-capture-mode=Everything",
            "--ignore-certificate-errors-spki-list=" + ",".join(spkis),
            "--disable-quic", "--no-first-run", "--disable-background-networking",
            "--disable-component-update", "--disable-sync", "--disable-domain-reliability"]
    if PROXIES[mode]:
        # <-loopback> removes Chrome's implicit "never proxy localhost" rule
        args += [f"--proxy-server={PROXIES[mode]}", "--proxy-bypass-list=<-loopback>"]
    browser = p.chromium.launch(executable_path=chrome_path(), headless=True, args=args)
    ctx = browser.new_context()
    page = ctx.new_page()
    cdp = ctx.new_cdp_session(page)
    cdp.send("Network.enable")
    cdp.send("Network.setCacheDisabled", {"cacheDisabled": True})
    reqs = {}
    cdp.on("Network.requestWillBeSent", lambda e: reqs.setdefault(e["requestId"], {}).update(
        url=e["request"]["url"], type=e.get("type"), ts=e["timestamp"]))
    def on_resp(e):
        r = e["response"]
        reqs.setdefault(e["requestId"], {}).update(
            protocol=r.get("protocol"), conn=r.get("connectionId"), timing=r.get("timing"),
            issuer=(r.get("securityDetails") or {}).get("issuer"), ip=r.get("remoteIPAddress"))
    cdp.on("Network.responseReceived", on_resp)
    cdp.on("Network.loadingFinished", lambda e: reqs.setdefault(e["requestId"], {}).update(end=e["timestamp"]))
    t0 = time.time()
    page.goto(URL, wait_until="load", timeout=120000)
    page.wait_for_function("window.__doneMs !== undefined", timeout=120000)
    done_ms = page.evaluate("window.__doneMs")
    status = page.inner_text("#status")
    rt = page.evaluate("""performance.getEntriesByType('resource').map(e => ({name: e.name,
        proto: e.nextHopProtocol, fetchStart: e.fetchStart, requestStart: e.requestStart, responseEnd: e.responseEnd}))""")
    page.wait_for_timeout(300)
    browser.close()  # flushes the netlog
    rows = []
    for rid, r in reqs.items():
        t = r.get("timing")
        if not t or not r.get("url", "").startswith("http"):
            continue
        firsts = [t[k] for k in ("proxyStart", "dnsStart", "connectStart", "sendStart") if t.get(k, -1) >= 0]
        stalled = min(firsts) if firsts else 0.0
        queueing = (t["requestTime"] - r["ts"]) * 1000
        rows.append({"url": r["url"].replace(URL.rstrip("/"), ""), "type": r.get("type"), "protocol": r.get("protocol"),
                     "conn": r.get("conn"), "issuer": r.get("issuer"),
                     "start_ms": round((r["ts"]) * 1000, 1),
                     "queueing_ms": round(queueing, 1), "stalled_ms": round(stalled, 1),
                     "blocked_ms": round(queueing + stalled, 1),  # DevTools Queueing + Stalled
                     "ttfb_ms": round(t["receiveHeadersEnd"] - t["sendStart"], 1) if t.get("sendStart", -1) >= 0 else None,
                     "total_ms": round((r["end"] - r["ts"]) * 1000, 1) if r.get("end") else None})
    base = min(x["start_ms"] for x in rows)
    for x in rows:
        x["start_ms"] = round(x["start_ms"] - base, 1)
    return {"done_ms": round(done_ms, 1), "status": status, "requests": rows, "resource_timing": rt}


def summarize(mode, run):
    rows = run["requests"]
    st = [r["stalled_ms"] for r in rows]
    bl = [r["blocked_ms"] for r in rows]
    return {"mode": mode, "page_done_ms": run["done_ms"], "requests": len(rows),
            "protocols": sorted({r["protocol"] for r in rows}),
            "distinct_connection_ids": len({r["conn"] for r in rows}),
            "cert_issuer": sorted({r["issuer"] for r in rows if r["issuer"]}),
            "stalled_sum_ms": round(sum(st)), "stalled_median_ms": round(statistics.median(st), 1), "stalled_max_ms": round(max(st)),
            "queue+stall_sum_ms": round(sum(bl)), "queue+stall_median_ms": round(statistics.median(bl), 1), "queue+stall_max_ms": round(max(bl)),
            "rt_nextHopProtocol": sorted({e["proto"] for e in run["resource_timing"]})}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=PROXIES)
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--out", default=str(ROOT / "results"))
    a = ap.parse_args()
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    summaries = []
    with sync_playwright() as p:
        for i in range(a.runs):
            netlog = out / f"netlog-{a.mode}-run{i+1}.json"
            run = one_run(p, a.mode, str(netlog))
            s = summarize(a.mode, run); s["run"] = i + 1; s["netlog"] = str(netlog.relative_to(ROOT))
            summaries.append(s)
            (out / f"requests-{a.mode}-run{i+1}.json").write_text(json.dumps(run, indent=1))
            print(json.dumps(s))
    (out / f"summary-{a.mode}.json").write_text(json.dumps(summaries, indent=1))


if __name__ == "__main__":
    main()
