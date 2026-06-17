#!/usr/bin/env python3
"""
Jira ↔ Trello sync (bidirectionnel par défaut).

Apparie chaque ticket Jira (JQL) avec une carte Trello via un marqueur caché
`[jira:KEY]` dans la description de la carte. Pour chaque champ, le côté le plus
récemment modifié gagne (Jira `updated` vs Trello `dateLastActivity`) — et on
n'écrit QUE si la valeur diffère (pas de ping-pong).

Champs synchronisés :
  - résumé / nom de carte        (bidirectionnel)
  - échéance (duedate / due)     (bidirectionnel)
  - statut ↔ liste               (bidirectionnel ; le nom de liste = nom de statut)
  - description                  (Jira → Trello, autorité Jira ; ADF aplati)
  - type, étiquettes             (Jira → Trello)

Création :
  - ticket Jira sans carte       → carte créée
  - carte Trello sans marqueur   → ticket Jira créé puis carte re-liée
Cartes dont le ticket sort du JQL → archivées (jamais supprimées).

SYNC_DIRECTION : "bidirectional" (défaut) | "jira-to-trello" | "trello-to-jira".

Stdlib uniquement. Env requis : voir README.
"""
import os, sys, json, base64, datetime, urllib.parse, urllib.request, urllib.error

def env(n, d=None, req=False):
    v = os.environ.get(n, d)
    if req and not v:
        sys.exit(f"Missing required env var: {n}")
    return v

JIRA_SITE    = env("JIRA_SITE", req=True).rstrip("/")
JIRA_EMAIL   = env("JIRA_EMAIL", req=True)
JIRA_TOKEN   = env("JIRA_TOKEN", req=True)
JIRA_PROJECT = env("JIRA_PROJECT", "")
JIRA_JQL     = env("JIRA_JQL", "") or (f'project = "{JIRA_PROJECT}" ORDER BY Rank ASC' if JIRA_PROJECT else "")
JIRA_ISSUETYPE_ID = env("JIRA_ISSUETYPE_ID", "10042")  # défaut: Tâche
# Map assignés Jira ↔ Trello : {"<jiraAccountId>": "<trelloMemberId>", ...}
try:
    ASSIGNEE_MAP = json.loads(env("ASSIGNEE_MAP", "") or "{}")
except Exception:
    ASSIGNEE_MAP = {}
ASSIGNEE_MAP_REV = {v: k for k, v in ASSIGNEE_MAP.items()}
TRELLO_KEY   = env("TRELLO_KEY", req=True)
TRELLO_TOKEN = env("TRELLO_TOKEN", req=True)
TRELLO_BOARD = env("TRELLO_BOARD", req=True)
DIRECTION    = env("SYNC_DIRECTION", "bidirectional")
if not JIRA_JQL:
    sys.exit("Provide JIRA_PROJECT or JIRA_JQL.")
TO_TRELLO = DIRECTION in ("bidirectional", "jira-to-trello")
TO_JIRA   = DIRECTION in ("bidirectional", "trello-to-jira")
ARCHIVE_LIST = "✓ Archivées (Jira)"

# ── HTTP ────────────────────────────────────────────────────────────────────
def _http(method, url, headers=None, body=None):
    req = urllib.request.Request(url, method=method, headers=headers or {})
    if body is not None:
        req.data = body
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read().decode().strip()
            # NB: `"" in "{["` vaut True en Python → tester l'appartenance à un tuple.
            return r.status, (json.loads(raw) if raw[:1] in ("{", "[") else raw)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()

def jira(method, path, params=None, body=None):
    url = f"{JIRA_SITE}/rest/api/3{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    auth = base64.b64encode(f"{JIRA_EMAIL}:{JIRA_TOKEN}".encode()).decode()
    h = {"Authorization": f"Basic {auth}", "Accept": "application/json"}
    data = None
    if body is not None:
        h["Content-Type"] = "application/json"; data = json.dumps(body).encode()
    return _http(method, url, h, data)

def trello(method, path, **params):
    params["key"] = TRELLO_KEY; params["token"] = TRELLO_TOKEN
    return _http(method, f"https://api.trello.com/1{path}?" + urllib.parse.urlencode(params))

# ── Helpers ─────────────────────────────────────────────────────────────────
def adf_to_text(node):
    if node is None: return ""
    if isinstance(node, str): return node
    out = []
    if isinstance(node, dict):
        if node.get("type") == "text": out.append(node.get("text", ""))
        for c in node.get("content", []) or []: out.append(adf_to_text(c))
        if node.get("type") in ("paragraph", "heading", "listItem"): out.append("\n")
    elif isinstance(node, list):
        for c in node: out.append(adf_to_text(c))
    return "".join(out)

def text_to_adf(text):
    paras = [p for p in (text or "").split("\n")]
    content = [{"type": "paragraph",
                "content": ([{"type": "text", "text": p}] if p else [])} for p in paras] or \
              [{"type": "paragraph", "content": []}]
    return {"type": "doc", "version": 1, "content": content}

def parse_ts(s):
    if not s: return datetime.datetime.min.replace(tzinfo=datetime.timezone.utc)
    s = s.replace("Z", "+00:00")
    # Jira: +0000 → +00:00
    if len(s) >= 5 and s[-5] in "+-" and s[-3] != ":":
        s = s[:-2] + ":" + s[-2:]
    try:
        return datetime.datetime.fromisoformat(s)
    except ValueError:
        return datetime.datetime.min.replace(tzinfo=datetime.timezone.utc)

def marker(key): return f"[jira:{key}]"
def due_day(iso): return iso[:10] if iso else None  # ISO/date → YYYY-MM-DD

def jira_search():
    fields = "summary,description,status,duedate,issuetype,labels,priority,updated,assignee,components"
    token = None
    out = []
    while True:
        code, data = jira("GET", "/search/jql", params={
            "jql": JIRA_JQL, "fields": fields, "maxResults": 100,
            **({"nextPageToken": token} if token else {})})
        if code == 200 and isinstance(data, dict):
            out += data.get("issues", [])
            token = data.get("nextPageToken")
            if not token or data.get("isLast", True): return out
            continue
        # fallback /search classique
        start, out = 0, []
        while True:
            code, data = jira("GET", "/search", params={
                "jql": JIRA_JQL, "fields": fields, "maxResults": 100, "startAt": start})
            if code != 200 or not isinstance(data, dict):
                sys.exit(f"Jira search failed: {code} {str(data)[:300]}")
            out += data.get("issues", [])
            start += len(data.get("issues", []))
            if start >= data.get("total", 0) or not data.get("issues"): return out

def jira_transition(key, target):
    code, data = jira("GET", f"/issue/{key}/transitions")
    if code != 200 or not isinstance(data, dict): return False
    tid = next((t["id"] for t in data.get("transitions", []) if t["to"]["name"] == target), None)
    if not tid: return False
    code, _ = jira("POST", f"/issue/{key}/transitions", body={"transition": {"id": tid}})
    return code in (200, 204)

def sync_comments(key, cid):
    """Commentaires bidirectionnels, anti-boucle par marqueurs :
    miroir d'un commentaire Jira #J côté Trello → texte « ↪ Jira #J … » ;
    miroir d'un commentaire Trello #T côté Jira → « ↪ Trello #T … »."""
    n = 0
    _, jc = jira("GET", f"/issue/{key}/comment", params={"maxResults": 100})
    jcomments = jc.get("comments", []) if isinstance(jc, dict) else []
    _, tacts = trello("GET", f"/cards/{cid}/actions", filter="commentCard", limit="50")
    tcomments = tacts if isinstance(tacts, list) else []
    jtexts = [adf_to_text(c.get("body")) for c in jcomments]
    ttexts = [(a.get("data", {}) or {}).get("text", "") for a in tcomments]

    if TO_TRELLO:
        for c in jcomments:
            jid = c["id"]
            if any(f"↪ Jira #{jid}" in t for t in ttexts):
                continue
            author = (c.get("author") or {}).get("displayName", "Jira")
            body = adf_to_text(c.get("body")).strip()
            if not body:
                continue
            trello("POST", f"/cards/{cid}/actions/comments", text=f"↪ Jira #{jid} · {author} : {body}")
            n += 1
    if TO_JIRA:
        for a in tcomments:
            text = (a.get("data", {}) or {}).get("text", "")
            if text.startswith("↪ Jira #"):
                continue  # c'est déjà un miroir d'un commentaire Jira
            tid = a["id"]
            if any(f"↪ Trello #{tid}" in t for t in jtexts):
                continue
            author = (a.get("memberCreator") or {}).get("fullName", "Trello")
            jira("POST", f"/issue/{key}/comment",
                 body={"body": text_to_adf(f"↪ Trello #{tid} · {author} : {text}")})
            n += 1
    return n

# ── Sync ────────────────────────────────────────────────────────────────────
def main():
    print(f"Direction: {DIRECTION}")
    code, board = trello("GET", f"/boards/{TRELLO_BOARD}", fields="id,name")
    if code != 200: sys.exit(f"Trello board not found: {code} {board}")
    bid = board["id"]; print(f"Board: {board['name']} ({bid})")

    lists = {l["name"]: l["id"] for l in trello("GET", f"/boards/{bid}/lists")[1]}
    listname = {v: k for k, v in lists.items()}
    labels = {l["name"]: l["id"] for l in trello("GET", f"/boards/{bid}/labels")[1] if l["name"]}
    cards = trello("GET", f"/boards/{bid}/cards",
                   fields="id,name,desc,due,idList,idLabels,idMembers,dateLastActivity")[1]

    by_key, unlinked = {}, []
    for c in cards:
        k = None
        for line in (c.get("desc") or "").splitlines():
            line = line.strip()
            if line.startswith("[jira:") and line.endswith("]"): k = line[6:-1]
        (by_key.__setitem__(k, c) if k else unlinked.append(c))

    LABEL_COLORS = {"Story": "green", "Bug": "red", "Task": "blue", "Tâche": "blue",
                    "Epic": "purple", "Fonctionnalité": "lime", "Feature": "lime",
                    "Sous-tâche": "sky", "Subtask": "sky"}
    def ensure_list(name):
        if name not in lists:
            _, l = trello("POST", f"/boards/{bid}/lists", name=name, pos="bottom")
            lists[name] = l["id"]; listname[l["id"]] = name
        return lists[name]
    def ensure_label(name):
        if not name: return None
        if name not in labels:
            code, l = trello("POST", f"/boards/{bid}/labels", name=name, color=LABEL_COLORS.get(name, "sky"))
            if code != 200 or not isinstance(l, dict) or "id" not in l: return None
            labels[name] = l["id"]
        return labels[name]
    def card_body(it):
        f = it["fields"]; key = it["key"]
        body = adf_to_text(f.get("description")).strip()
        return f"{body}\n\n— {key} · {JIRA_SITE}/browse/{key}\n{marker(key)}".strip()

    issues = {it["key"]: it for it in jira_search()}
    print(f"{len(issues)} ticket(s) Jira · {len(by_key)} carte(s) liée(s) · {len(unlinked)} carte(s) non liée(s)")

    # ── 1. Cartes Trello non liées → créer le ticket Jira (TO_JIRA) ──────────
    for c in unlinked if TO_JIRA else []:
        cur_status = listname.get(c["idList"], "À faire")
        fields = {"project": {"key": JIRA_PROJECT or JIRA_JQL.split('"')[1]},
                  "issuetype": {"id": JIRA_ISSUETYPE_ID}, "summary": c["name"],
                  "description": text_to_adf((c.get("desc") or "").strip())}
        if c.get("due"): fields["duedate"] = due_day(c["due"])
        code, r = jira("POST", "/issue", body={"fields": fields})
        if code in (200, 201):
            key = r["key"]
            if cur_status not in ("À faire", "To Do", "Backlog"):
                jira_transition(key, cur_status)
            newdesc = ((c.get("desc") or "").rstrip() + f"\n\n— {key} · {JIRA_SITE}/browse/{key}\n{marker(key)}").strip()
            trello("PUT", f"/cards/{c['id']}", desc=newdesc)
            issues[key] = {"key": key, "fields": {}}  # évite l'archivage immédiat
            print(f"  ⊕ Jira {key} créé depuis carte « {c['name']} »")
        else:
            print(f"  ✗ création Jira échouée pour « {c['name']} » : {code} {str(r)[:120]}")

    # ── 2. Paires appariées → réconciliation champ par champ ────────────────
    for key, it in issues.items():
        c = by_key.get(key)
        f = it.get("fields", {})
        if not c:
            if not TO_TRELLO: continue
            # ticket sans carte → créer la carte
            status = (f.get("status") or {}).get("name", "À faire")
            params = {"idList": ensure_list(status), "name": f.get("summary", key),
                      "desc": card_body(it), "pos": "bottom"}
            if f.get("duedate"): params["due"] = f["duedate"] + "T12:00:00.000Z"
            lid = ensure_label((f.get("issuetype") or {}).get("name"))
            if lid: params["idLabels"] = lid
            trello("POST", "/cards", **params)
            print(f"  + carte créée pour {key}")
            continue

        jnewer = parse_ts(f.get("updated")) >= parse_ts(c.get("dateLastActivity"))
        cid = c["id"]
        changes = []

        # nom / résumé
        jsum = f.get("summary", ""); cname = c.get("name", "")
        if jsum != cname:
            if jnewer and TO_TRELLO:
                trello("PUT", f"/cards/{cid}", name=jsum); changes.append("nom→Trello")
            elif (not jnewer) and TO_JIRA:
                jira("PUT", f"/issue/{key}", body={"fields": {"summary": cname}}); changes.append("nom→Jira")

        # échéance
        jdue = f.get("duedate"); cdue = due_day(c.get("due"))
        if jdue != cdue:
            if jnewer and TO_TRELLO:
                trello("PUT", f"/cards/{cid}", due=(jdue + "T12:00:00.000Z") if jdue else "")
                changes.append("échéance→Trello")
            elif (not jnewer) and TO_JIRA:
                jira("PUT", f"/issue/{key}", body={"fields": {"duedate": cdue}}); changes.append("échéance→Jira")

        # statut ↔ liste
        jstatus = (f.get("status") or {}).get("name", "")
        clist = listname.get(c["idList"], "")
        if jstatus and clist and jstatus != clist:
            if jnewer and TO_TRELLO:
                trello("PUT", f"/cards/{cid}", idList=ensure_list(jstatus)); changes.append(f"statut→Trello({jstatus})")
            elif (not jnewer) and TO_JIRA:
                if jira_transition(key, clist): changes.append(f"statut→Jira({clist})")

        # description : autorité Jira → Trello
        if TO_TRELLO:
            want = card_body(it)
            if (c.get("desc") or "").strip() != want:
                trello("PUT", f"/cards/{cid}", desc=want); changes.append("desc→Trello")
            lid = ensure_label((f.get("issuetype") or {}).get("name"))
            if lid and lid not in (c.get("idLabels") or []):
                trello("POST", f"/cards/{cid}/idLabels", value=lid)
            # composants Jira → étiquettes Trello
            for comp in f.get("components") or []:
                clid = ensure_label(comp.get("name"))
                if clid and clid not in (c.get("idLabels") or []):
                    trello("POST", f"/cards/{cid}/idLabels", value=clid)

        # assigné ↔ membre (bidirectionnel, via ASSIGNEE_MAP)
        if ASSIGNEE_MAP:
            jacct = (f.get("assignee") or {}).get("accountId")
            want_member = ASSIGNEE_MAP.get(jacct) if jacct else None
            cur_mapped = [m for m in (c.get("idMembers") or []) if m in ASSIGNEE_MAP_REV]
            cur_member = cur_mapped[0] if cur_mapped else None
            if want_member != cur_member:
                if jnewer and TO_TRELLO:
                    for m in cur_mapped:
                        trello("DELETE", f"/cards/{cid}/idMembers/{m}")
                    if want_member:
                        trello("POST", f"/cards/{cid}/idMembers", value=want_member)
                    changes.append("assigné→Trello")
                elif (not jnewer) and TO_JIRA:
                    acct = ASSIGNEE_MAP_REV.get(cur_member) if cur_member else None
                    jira("PUT", f"/issue/{key}/assignee", body={"accountId": acct})
                    changes.append("assigné→Jira")

        # commentaires (bidirectionnel, anti-boucle par marqueurs)
        nc = sync_comments(key, cid)
        if nc: changes.append(f"{nc} commentaire(s)")

        if changes: print(f"  ↻ {key}: {', '.join(changes)}")

    # ── 3. Cartes liées dont le ticket a quitté le JQL → archiver ───────────
    if TO_TRELLO:
        n = 0
        for key, c in by_key.items():
            if key not in issues:
                trello("PUT", f"/cards/{c['id']}", idList=ensure_list(ARCHIVE_LIST)); n += 1
        if n: print(f"  ⤓ {n} carte(s) archivée(s).")

    print("Sync terminé.")

if __name__ == "__main__":
    main()
