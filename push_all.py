import base64
import json
import os
import subprocess
import urllib.request

REPO = "2744317644/wancg-downloader"
TOKEN = subprocess.check_output(["gh", "auth", "token"], text=True).strip()


def api(method, path, payload=None):
    request = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}{path}",
        data=json.dumps(payload).encode("utf-8") if payload is not None else None,
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
            "User-Agent": "wnacg-build",
        },
        method=method,
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read())


ref = api("GET", "/git/ref/heads/main")
base = ref["object"]["sha"]
base_commit = api("GET", f"/git/commits/{base}")
base_tree = base_commit["tree"]["sha"]

raw = subprocess.check_output(
    ["git", "-c", "core.quotePath=false", "ls-files", "-z"]
)
paths = [item.decode("utf-8") for item in raw.split(b"\0") if item]
# include new untracked source files
raw_other = subprocess.check_output(
    ["git", "-c", "core.quotePath=false", "ls-files", "--others",
     "--exclude-standard", "-z"]
)
for item in raw_other.split(b"\0"):
    if item:
        path = item.decode("utf-8")
        if path not in paths and not path.startswith(".gh-"):
            paths.append(path)

tree = []
for path in paths:
    with open(path, "rb") as handle:
        content = base64.b64encode(handle.read()).decode("ascii")
    blob = api("POST", "/git/blobs", {"content": content, "encoding": "base64"})
    tree.append({
        "path": path.replace("\\", "/"),
        "mode": "100644",
        "type": "blob",
        "sha": blob["sha"],
    })
    print("blob", path)

new_tree = api("POST", "/git/trees", {"base_tree": base_tree, "tree": tree})
commit = api("POST", "/git/commits", {
    "message": "Add tab bar, home browser, files preview and Liquid Glass",
    "tree": new_tree["sha"],
    "parents": [base],
})
api("PATCH", "/git/refs/heads/main", {"sha": commit["sha"], "force": True})
print("pushed", commit["sha"])
