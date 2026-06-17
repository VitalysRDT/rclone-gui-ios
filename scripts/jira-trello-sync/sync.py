#!/usr/bin/env python3
"""
Jira → Trello one-way sync (source of truth = Jira).

For each Jira issue matching JIRA_JQL, ensures a matching Trello card exists on
the target board and keeps it up to date:
  - summary      → card name
  - description  → card description (ADF flattened to text) + Jira link
  - status       → Trello list (auto-created per distinct status)
  - duedate      → card due date
  - issuetype    → Trello label (auto-created)

Idempotent: each card carries a hidden marker `[jira:KEY]` in its description;
re-runs update the existing card instead of duplicating. Cards whose Jira issue
disappeared from the JQL result are moved to a "✓ Archivées (Jira)" list (never
deleted, to stay safe).

No third-party deps — standard library only (runs on GitHub Actions Python).

Required env (set as GitHub Secrets):
  JIRA_SITE     e.g. https://yourname.atlassian.net
  JIRA_EMAIL    Atlassian account email
  JIRA_TOKEN    Atlassian API token (id.atlassian.com → API tokens)
  JIRA_PROJECT  project key, e.g. RG          (used if JIRA_JQL is unset)
  JIRA_JQL      optional, overrides the default project query
  TRELLO_KEY    Trello Power-Up API key
  TRELLO_TOKEN  Trello token (Atlassian API token works too)
  TRELLO_BOARD  target board shortlink or id (use a DEDICATED board, not the
                hand-curated roadmap board)
"""
import os, sys, json, base64, urllib.parse, urllib.request, urllib.error

def env(name, default=None, required=False):
    v = os.environ.get(name, default)
    if required and not v:
        sys.exit(f"Missing required env var: {name}")
    return v

JIRA_SITE   = (env("JIRA_SITE", required=True)).rstrip("/")
JIRA_EMAIL  = env("JIRA_EMAIL", required=True)
JIRA_TOKEN  = env("JIRA_TOKEN", required=True)
JIRA_PROJECT= env("JIRA_PROJECT", "")
JIRA_JQL    = env("JIRA_JQL", "") or (f'project = "{JIRA_PROJECT}" ORDER BY Rank ASC' if JIRA_PROJECT else "")
TRELLO_KEY  = env("TRELLO_KEY", required=True)
TRELLO_TOKEN= env("TRELLO_TOKEN", required=True)
TRELLO_BOARD= env("TRELLO_BOARD", required=True)
if not JIRA_JQL:
    sys.exit("Provide JIRA_PROJECT or JIRA_JQL.")

ARCHIVE_LIST = "✓ Archivées (Jira)"

# ── HTTP ────────────────────────────────────────────────────────────────────
def _http(method, url, headers=None, body=None):
    req = urllib.request.Request(url, method=method, headers=headers or {})
    if body is not None:
        req.data = body
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw[:1] in "{[" else raw)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()

def jira(method, path, params=None, body=None):
    url = f"{JIRA_SITE}/rest/api/3{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    auth = base64.b64encode(f"{JIRA_EMAIL}:{JIRA_TOKEN}".encode()).decode()
    headers = {"Authorization": f"Basic {auth}", "Accept": "application/json"}
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    return _http(method, url, headers, data)

def trello(method, path, **params):
    params["key"] = TRELLO_KEY
    params["token"] = TRELLO_TOKEN
    url = f"https://api.trello.com/1{path}?" + urllib.parse.urlencode(params)
    return _http(method, url)

# ── Helpers ─────────────────────────────────────────────────────────────────
def adf_to_text(node):
    """Flatten an Atlassian Document Format node into plain text."""
    if node is None:
        return ""
    if isinstance(node, str):
        return node
    out = []
    if isinstance(node, dict):
        if node.get("type") == "text":
            out.append(node.get("text", ""))
        for child in node.get("content", []) or []:
            out.append(adf_to_text(child))
        if node.get("type") in ("paragraph", "heading", "listItem"):
            out.append("\n")
    elif isinstance(node, list):
        for child in node:
            out.append(adf_to_text(child))
    return "".join(out)

def marker(key):
    return f"[jira:{key}]"

def jira_search():
    """Fetch issues. Tries the enhanced /search/jql endpoint, falls back to the
    classic /search for older sites."""
    fields = "summary,description,status,duedate,issuetype,labels"
    issues, token = [], None
    while True:
        code, data = jira("GET", "/search/jql", params={
            "jql": JIRA_JQL, "fields": fields, "maxResults": 100,
            **({"nextPageToken": token} if token else {})
        })
        if code == 200 and isinstance(data, dict):
            issues += data.get("issues", [])
            token = data.get("nextPageToken")
            if not token or data.get("isLast", True):
                return issues
            continue
        # Fallback: classic /search (deprecated but still live on many sites)
        start = 0
        issues = []
        while True:
            code, data = jira("GET", "/search", params={
                "jql": JIRA_JQL, "fields": fields, "maxResults": 100, "startAt": start
            })
            if code != 200 or not isinstance(data, dict):
                sys.exit(f"Jira search failed: {code} {str(data)[:300]}")
            issues += data.get("issues", [])
            start += len(data.get("issues", []))
            if start >= data.get("total", 0) or not data.get("issues"):
                return issues

# ── Sync ────────────────────────────────────────────────────────────────────
def main():
    code, board = trello("GET", f"/boards/{TRELLO_BOARD}", fields="id,name")
    if code != 200:
        sys.exit(f"Trello board not found: {code} {board}")
    bid = board["id"]
    print(f"Board: {board['name']} ({bid})")

    # Existing lists / labels / cards on the board
    lists = {l["name"]: l["id"] for l in trello("GET", f"/boards/{bid}/lists")[1]}
    labels = {l["name"]: l["id"] for l in trello("GET", f"/boards/{bid}/labels")[1] if l["name"]}
    cards = trello("GET", f"/boards/{bid}/cards", fields="id,name,desc,due,idList,idLabels")[1]

    # Index existing cards by their Jira marker
    by_key = {}
    for c in cards:
        for line in (c.get("desc") or "").splitlines():
            line = line.strip()
            if line.startswith("[jira:") and line.endswith("]"):
                by_key[line[6:-1]] = c

    # Couleurs Trello valides uniquement (pas de "light-gray"). Défaut = sky.
    LABEL_COLORS = {"Story": "green", "Bug": "red", "Task": "blue", "Tâche": "blue",
                    "Epic": "purple", "Fonctionnalité": "lime", "Feature": "lime",
                    "Sous-tâche": "sky", "Subtask": "sky"}

    def ensure_list(name):
        if name not in lists:
            _, l = trello("POST", f"/boards/{bid}/lists", name=name, pos="bottom")
            lists[name] = l["id"]
        return lists[name]

    def ensure_label(name):
        if not name:
            return None
        if name not in labels:
            code, l = trello("POST", f"/boards/{bid}/labels", name=name,
                             color=LABEL_COLORS.get(name, "sky"))
            if code != 200 or not isinstance(l, dict) or "id" not in l:
                return None  # création échouée → on continue sans étiquette
            labels[name] = l["id"]
        return labels[name]

    issues = jira_search()
    print(f"{len(issues)} issue(s) from Jira.")
    seen = set()

    for it in issues:
        key = it["key"]
        seen.add(key)
        f = it.get("fields", {})
        status = (f.get("status") or {}).get("name", "À faire")
        itype = (f.get("issuetype") or {}).get("name", "")
        summary = f.get("summary", key)
        due = f.get("duedate")  # YYYY-MM-DD or None
        body = adf_to_text(f.get("description")).strip()
        link = f"{JIRA_SITE}/browse/{key}"
        desc = f"{body}\n\n— {key} · {link}\n{marker(key)}".strip()

        list_id = ensure_list(status)
        label_id = ensure_label(itype)
        due_iso = (due + "T12:00:00.000Z") if due else ""

        if key in by_key:
            cid = by_key[key]["id"]
            params = {"name": summary, "desc": desc, "idList": list_id}
            if due_iso:
                params["due"] = due_iso
            trello("PUT", f"/cards/{cid}", **params)
            if label_id and label_id not in (by_key[key].get("idLabels") or []):
                trello("POST", f"/cards/{cid}/idLabels", value=label_id)
            print(f"  ↻ {key} → {status}")
        else:
            params = {"idList": list_id, "name": summary, "desc": desc, "pos": "bottom"}
            if due_iso:
                params["due"] = due_iso
            if label_id:
                params["idLabels"] = label_id
            trello("POST", "/cards", **params)
            print(f"  + {key} → {status}")

    # Archive cards whose Jira issue is no longer in scope (never delete)
    archived = 0
    for key, c in by_key.items():
        if key not in seen:
            trello("PUT", f"/cards/{c['id']}", idList=ensure_list(ARCHIVE_LIST))
            archived += 1
    if archived:
        print(f"  ⤓ {archived} carte(s) archivée(s) (absentes du JQL).")

    print("Sync terminé.")

if __name__ == "__main__":
    main()
