# Jira ↔ Trello sync (bidirectionnel)

Automatisation **Jira ↔ Trello** tournant en **GitHub Actions**
(`.github/workflows/jira-trello-sync.yml`), toutes les 30 min + déclenchement
manuel. Aucun credential dans le dépôt : tout passe par les **GitHub Secrets**.

Chaque ticket Jira (retenu par le JQL) est apparié à une carte Trello via un
marqueur caché `[jira:KEY]`. **Réconciliation champ par champ** : le côté le plus
récemment modifié gagne (Jira `updated` vs Trello `dateLastActivity`), et on
n'écrit que si la valeur diffère (pas de ping-pong).

| Champ | Sens |
|---|---|
| résumé ↔ nom de carte | bidirectionnel |
| échéance (`duedate` ↔ `due`) | bidirectionnel |
| **statut ↔ liste** (nom de liste = nom de statut, transition Jira) | bidirectionnel |
| description (ADF aplati + lien) | Jira → Trello (autorité Jira) |
| type, étiquettes | Jira → Trello |

**Création** : un ticket Jira sans carte → carte créée ; une **carte Trello sans
marqueur** → ticket Jira créé puis carte re-liée. Cartes dont le ticket sort du
JQL → **archivées** (jamais supprimées). Le sens est réglable via
`SYNC_DIRECTION` (`bidirectional` | `jira-to-trello` | `trello-to-jira`).

## 1. Créer un board Trello dédié

⚠️ **N'utilise pas le board roadmap** (curé à la main) comme cible — le sync y
créerait des listes de statut Jira. Crée un board vide « Jira mirror » et
récupère son shortlink (l'identifiant dans l'URL `trello.com/b/XXXXXXXX`).

## 2. Obtenir les credentials

| Secret | Où l'obtenir |
|---|---|
| `JIRA_SITE` | `https://<ton-site>.atlassian.net` |
| `JIRA_EMAIL` | ton email de compte Atlassian |
| `JIRA_TOKEN` | https://id.atlassian.com/manage-profile/security/api-tokens → *Create API token* |
| `JIRA_PROJECT` | clé du projet (ex. `RG`) — ou laisse vide et fournis `JIRA_JQL` |
| `JIRA_JQL` | *(optionnel)* requête JQL personnalisée, ex. `project = RG AND statusCategory != Done` |
| `TRELLO_KEY` | https://trello.com/power-ups/admin → ton Power-Up → *API key* |
| `TRELLO_TOKEN` | token Trello (Power-Up / authorize ; ⚠️ pas un token API Atlassian) |
| `TRELLO_BOARD` | shortlink/id du board mirror (étape 1) |
| `SYNC_DIRECTION` | *(optionnel)* `bidirectional` (défaut), `jira-to-trello` ou `trello-to-jira` |
| `JIRA_ISSUETYPE_ID` | *(optionnel)* type des tickets créés depuis une carte Trello (défaut `10042`) |

> Le **token API Atlassian** sert à la fois pour Jira (`JIRA_TOKEN`) et Trello
> (`TRELLO_TOKEN`) si tu utilises le même compte Atlassian.

## 3. Ajouter les secrets sur GitHub

Repo → **Settings → Secrets and variables → Actions → New repository secret**,
puis ajoute chacun des secrets ci-dessus. Tant que `JIRA_SITE` est absent, le
workflow s'exécute en **no-op** (étape « guard »).

## 4. Lancer

- Automatique : toutes les 30 min (cron `17,47 * * * *`).
- Manuel : onglet **Actions → Jira → Trello sync → Run workflow**.

## Test en local

```bash
export JIRA_SITE="https://xxx.atlassian.net" JIRA_EMAIL="…" JIRA_TOKEN="…" \
       JIRA_PROJECT="RG" TRELLO_KEY="…" TRELLO_TOKEN="…" TRELLO_BOARD="XXXXXXXX"
python3 scripts/jira-trello-sync/sync.py
```

## Notes

- **Bidirectionnel** par défaut, avec arbitrage **dernier-modifié-gagne** au niveau
  de chaque champ (pas d'écrasement aveugle, pas de ping-pong).
- Le mapping `statut ↔ liste` crée une liste Trello par statut Jira ; côté Jira,
  une transition est jouée vers le statut homonyme de la liste (si disponible
  dans le workflow).
- La **description** reste pilotée par Jira (autorité) : édite-la côté Jira.
- ⚠️ Cible un **board dédié** : déplacer/éditer une carte y est propagé à Jira.
- Aucune dépendance tierce : `sync.py` n'utilise que la bibliothèque standard.
