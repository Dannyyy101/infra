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

Zitadel liegt bisher in der Datenbank `zitadel` des labs-101-Postgres. Damit Nutzer, Clients und
Secrets erhalten bleiben:

1. Dump: `pg_dump -Fc -d zitadel > zitadel.dump` (auf dem alten Server)
2. Chart mit **demselben Masterkey** installieren, Zitadel auf 0 skalieren
   (`kubectl -n auth scale deploy auth-zitadel --replicas=0`)
3. Datenbank leeren und einspielen: `pg_restore --clean --if-exists -d zitadel zitadel.dump`
4. Zitadel wieder auf 1 skalieren, `start-from-init` führt nur noch Migrationen aus

Die Werte unter `zitadel.firstInstance` greifen nur bei einer leeren Datenbank.
