# Jira → Trello sync

Automatisation **Jira → Trello** (Jira = source de vérité) tournant en
**GitHub Actions** (`.github/workflows/jira-trello-sync.yml`), toutes les 30 min
+ déclenchement manuel. Aucun credential dans le dépôt : tout passe par les
**GitHub Secrets**.

Chaque ticket Jira retenu par le JQL crée/met à jour une carte Trello :
`summary → nom`, `description → desc` (ADF aplati + lien Jira), `status → liste`
(créée automatiquement), `duedate → échéance`, `issuetype → étiquette`. Le sync
est **idempotent** (marqueur `[jira:KEY]` dans la carte). Les cartes dont le
ticket disparaît du JQL sont **archivées** (jamais supprimées).

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
| `TRELLO_TOKEN` | token Trello (un token API Atlassian fonctionne aussi) |
| `TRELLO_BOARD` | shortlink/id du board mirror (étape 1) |

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

- **Sens unique** Jira → Trello : les modifications faites côté Trello sont
  écrasées au prochain sync. (Le bidirectionnel demande une gestion de conflits ;
  on peut l'ajouter si besoin.)
- Le mapping `status → liste` crée une liste Trello par statut Jira rencontré.
- Aucune dépendance tierce : `sync.py` n'utilise que la bibliothèque standard.
