import base64
import json
import os
import subprocess
import tempfile

REPO = "2744317644/wancg-downloader"


def api(method, path, payload=None):
    cmd = ["gh", "api", "--method", method, f"repos/{REPO}{path}"]
    temp_name = None
    if payload is not None:
        handle = tempfile.NamedTemporaryFile(
            "w", suffix=".json", delete=False, encoding="utf-8"
        )
        json.dump(payload, handle)
        handle.close()
        temp_name = handle.name
        cmd += ["--input", temp_name]
    try:
        output = subprocess.check_output(
            cmd, text=True, encoding="utf-8"
        )
    finally:
        if temp_name:
            os.unlink(temp_name)
    return json.loads(output)


ref = api("GET", "/git/ref/heads/main")
base = ref["object"]["sha"]
base_commit = api("GET", f"/git/commits/{base}")
base_tree = base_commit["tree"]["sha"]

raw = subprocess.check_output(
    ["git", "-c", "core.quotePath=false", "ls-files", "-z"]
)
paths = [item.decode("utf-8") for item in raw.split(b"\0") if item]
raw_other = subprocess.check_output(
    ["git", "-c", "core.quotePath=false", "ls-files", "--others",
     "--exclude-standard", "-z"]
)
for item in raw_other.split(b"\0"):
    if item:
        path = item.decode("utf-8")
        if path not in paths and not path.startswith(".gh-"):
            paths.append(path)

# Explicitly removed in this commit.
paths = [p for p in paths if p != "ios/Sources/FloatingTabBar.swift"]

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
    "message": "Restore the system Liquid Glass tab bar",
    "tree": new_tree["sha"],
    "parents": [base],
})
api("PATCH", "/git/refs/heads/main", {"sha": commit["sha"], "force": True})
print("pushed", commit["sha"])
