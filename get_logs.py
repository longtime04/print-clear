#!/usr/bin/env python3
"""下载 GitHub Actions 运行日志（跟随 302 到签名地址）。"""
import sys, urllib.request, urllib.error
sys.path.insert(0, "/opt/muse/skills/custom-connector-setup/bin")
from dynamic_credentials import add_surrogate_to_request

PROVIDER = "custom.github-classic"
run_id = sys.argv[1]
out = sys.argv[2]

class RedirectFound(Exception):
    def __init__(self, url):
        self.url = url

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise RedirectFound(newurl)

url = f"https://api.github.com/repos/longtime04/print-clear/actions/runs/{run_id}/logs"
req = urllib.request.Request(url, method="GET")
req.add_header("Accept", "application/vnd.github+json")
add_surrogate_to_request(req, PROVIDER, allowed_hosts=["api.github.com"])
try:
    with urllib.request.build_opener(NoRedirect()).open(req, timeout=60) as resp:
        print("unexpected status", resp.status)
        sys.exit(1)
except RedirectFound as r:
    print("redirect to:", r.url[:80], "...")
    urllib.request.urlretrieve(r.url, out)
    print("saved", out)
except urllib.error.HTTPError as e:
    print("HTTP", e.code, e.read().decode("utf-8", "replace")[:500])
    sys.exit(1)
