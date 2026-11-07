# auth

Zitadel als gemeinsamer Identity Provider für alle Apps (labs-101 und weitere), mit eigener PostgreSQL.
Jede App bekommt in Zitadel ein eigenes Projekt bzw. eine eigene Application und nutzt
`https://auth.project101.tech` als Issuer.

## Installieren

Secrets in `values-prod.local.yaml` (per `.gitignore` ausgeschlossen):

```yaml
secrets:
  masterkey: ...           # genau 32 Zeichen, nie mehr ändern
  postgresUsername: postgres
  postgresPassword: ...
  zitadelDbPassword: ...
  adminPassword: ...
ingress:
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: GRPC
    cert-manager.io/cluster-issuer: letsencrypt
```

```sh
helm upgrade --install auth helm/auth -n auth --create-namespace -f helm/auth/values-prod.local.yaml
```

## Umzug der bestehenden Instanz aus labs-101

Kurzfassung, die Befehle im Detail siehe Chat/Doku:

1. Masterkey der alten Instanz übernehmen, Postgres-Major-Version mindestens wie die alte
2. Chart mit `--set zitadel.enabled=false` installieren (nur Postgres)
3. Rolle und Datenbank `zitadel` anlegen (Passwort = `secrets.zitadelDbPassword`)
4. Alte Zitadel stoppen, `pg_dump -Fc -d zitadel` → `pg_restore --no-owner --no-privileges --role=zitadel -d zitadel`
5. `helm upgrade ... --set zitadel.enabled=true`, `start-from-init` führt nur noch Migrationen aus
6. Route von `auth.project101.tech` auf den neuen Service umstellen
7. Zitadel aus dem produktiven `docker-compose.yml` von labs-101 entfernen

Die Werte unter `zitadel.firstInstance` greifen nur bei einer leeren Datenbank.
