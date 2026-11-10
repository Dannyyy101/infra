# Argo CD

GitOps für den Cluster: Was in `main` dieses Repos steht, läuft im Cluster. Niemand ruft mehr `helm upgrade`
oder `kubectl apply` von Hand auf (Ausnahmen: der Bootstrap unten und die Secrets).

```
argocd/root.yaml          App of Apps, einmalig per kubectl apply
argocd/apps/*.yaml        eine Application pro Komponente
values/*.yaml             die Werte pro Komponente (Produktion, ohne Secrets)
```

| Application | Chart | Namespace | Release |
|---|---|---|---|
| `argocd` | `argo/argo-cd` | `argocd` | `argocd` |
| `cloudflared` | `helm/cloudflared` | `cloudflare` | `tunnel` |
| `auth` | `helm/auth` | `auth` | `auth` |
| `monitoring` | `prometheus-community/kube-prometheus-stack` | `monitoring` | `monitoring` |
| `labs-101` | `deploy/helm/labs-101` aus dem App-Repo | `labs-101` | `labs-101` |
| `rezepte` | `helm/rezepte` | `rezepte` | `rezepte` |
| `obsidian-web` | `helm/obsidian-web` | `obsidian-web` | `obsidian-web` |

Die Release-Namen entsprechen den bisherigen `helm install`, dadurch bleiben die Ressourcennamen gleich und
Argo CD übernimmt die laufenden Ressourcen, statt sie neu anzulegen (wichtig für die PVCs der Datenbanken).

**Deployments von labs-101:** Die CI im App-Repo (`.github/workflows/images.yaml`) baut die Images mit dem
Commit-SHA als Tag und committet die Tags nach `values/labs-101.yaml`. Argo CD deployt genau diesen Stand.
Ein Rollback ist ein `git revert` dieses Commits.

**Deployments von rezepte:** genauso, die CI von `Dannyyy101/rezepte` (`.github/workflows/image.yaml`) schreibt
`image.tag` in `values/rezepte.yaml`. Das Chart liegt hier unter `helm/rezepte`.

**Deployments von obsidian-web:** genauso, die CI von `Dannyyy101/obsidian-web` (`.github/workflows/docker.yml`)
schreibt `image.tag` in `values/obsidian-web.yaml`. Das Chart liegt hier unter `helm/obsidian-web`.

## Secrets

Dieses Repo ist öffentlich, Secrets stehen nie in den values. Die Charts lesen sie aus Secrets, die einmalig
von Hand angelegt werden (`existingSecret`). Später ersetzbar durch External Secrets oder SOPS, ohne dass
sich an den Charts etwas ändert.

```sh
# zitadel: aus dem bisherigen, vom Chart erzeugten Secret übernehmen (gleiche Keys, nur neuer Name)
kubectl -n auth get secret auth -o json \
  | jq '{apiVersion, kind, type, data, metadata: {name: "auth-secrets", namespace: "auth"}}' \
  | kubectl apply -f -

# argo cd: client der Application "Argo CD" in zitadel (siehe unten)
kubectl -n argocd create secret generic argocd-oidc \
  --from-literal=clientID=... --from-literal=clientSecret=...
kubectl -n argocd label secret argocd-oidc app.kubernetes.io/part-of=argocd

# grafana
kubectl create namespace monitoring
kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin --from-literal=admin-password="$(openssl rand -base64 24)"
kubectl -n monitoring create secret generic grafana-oidc \
  --from-literal=GF_AUTH_GENERIC_OAUTH_CLIENT_ID=... \
  --from-literal=GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=...

# labs-101: dieselben Werte wie die GitHub-Secrets des bisherigen docker-compose-Deployments
kubectl create namespace labs-101
kubectl -n labs-101 create secret generic labs-101-secrets \
  --from-literal=POSTGRES_USERNAME=... --from-literal=POSTGRES_PASSWORD=... \
  --from-literal=AUTH_CLIENT_ID=... --from-literal=AUTH_CLIENT_SECRET=... --from-literal=AUTH_SECRET=... \
  --from-literal=GEMINI_API_KEY=... --from-literal=CALENDAR_ENCRYPTION_KEY=...

# rezepte: Client der Application "Rezepte" in Zitadel (siehe unten), der Rest zufällig
kubectl create namespace rezepte
kubectl -n rezepte create secret generic rezepte-secrets \
  --from-literal=POSTGRES_PASSWORD="$(openssl rand -hex 24)" --from-literal=AUTH_SECRET="$(openssl rand -base64 32)" \
  --from-literal=AUTH_CLIENT_ID=... --from-literal=AUTH_CLIENT_SECRET=...
# nach einer Änderung am Secret: kubectl -n rezepte rollout restart deploy/rezepte

# obsidian-web: dieselben Werte wie in deploy/.env auf home-server (ZITADEL_CLIENT_ID, ZITADEL_CLIENT_SECRET,
# COOKIE_SECRET), der Client in Zitadel bleibt derselbe, weil sich der Host nicht ändert
kubectl create namespace obsidian-web
kubectl -n obsidian-web create secret generic obsidian-web-secrets \
  --from-literal=OAUTH2_PROXY_CLIENT_ID=... --from-literal=OAUTH2_PROXY_CLIENT_SECRET=... \
  --from-literal=OAUTH2_PROXY_COOKIE_SECRET=...
# nach einer Änderung am Secret: kubectl -n obsidian-web rollout restart deploy/obsidian-web
```

Den Namen des bisherigen Zitadel-Secrets vorher mit `kubectl -n auth get secrets` prüfen.

## Zitadel: Zugang zu Argo CD und Grafana

Zitadel ist mit allen Nutzern von labs-101 geteilt. Ohne Einschränkung könnte sich jeder von ihnen anmelden.

1. Neues Projekt `infra` anlegen, in den Einstellungen des Projekts:
   - **Assert Roles on Authentication** an (die Rollen kommen in Token und Userinfo)
   - **Check authorization on Authentication** an (ohne Rolle in diesem Projekt keine Anmeldung)
2. Rolle `admin` anlegen und dir unter Authorizations zuweisen.
3. Zwei Applications vom Typ Web, Code Flow, Client Secret (Basic):
   - Argo CD, Redirect URI `https://argocd.project101.tech/auth/callback`
   - Grafana, Redirect URI `https://grafana.project101.tech/login/generic_oauth`
4. Deine User-ID (Users → du → ID) in `values/argocd.yaml` bei `REPLACE_WITH_ZITADEL_USER_ID` eintragen.
   Argo CD prüft zusätzlich selbst: Ohne diesen Eintrag hat auch ein angemeldeter Nutzer keine Rechte.

## Zitadel: Login für rezepte

Alle Nutzer von Zitadel dürfen ins Rezeptbuch, es gibt keine Rollen.

1. Neues Projekt `rezepte` anlegen (ohne "Check authorization on Authentication").
2. Application vom Typ Web, Code Flow, Client Secret (Basic):
   - Redirect URI `https://rezepte.project101.tech/auth/callback`
   - Post Logout URI `https://rezepte.project101.tech/anmelden`
   - Refresh Token an (Token-Einstellungen der Application)
3. Client-ID und -Secret in `rezepte-secrets` eintragen (oben) und `rollout restart`.

## Bootstrap

```sh
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd --version 10.14.0 -n argocd --create-namespace -f values/argocd.yaml
# secrets anlegen (oben), dann:
kubectl apply -f argocd/root.yaml
```

Ab jetzt verwaltet Argo CD auch sich selbst. Anmeldung vor dem Tunnel per
`kubectl -n argocd port-forward svc/argocd-server 8080:80`, Benutzer `admin`, Passwort:
`kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`.
Sobald die Anmeldung über Zitadel klappt, das Secret löschen und `admin.enabled: false` setzen.

## Routen im Cloudflare-Tunnel

Im Dashboard (Modus `token`) unter Public Hostnames:

| Hostname | Service |
|---|---|
| `argocd.project101.tech` | `http://argocd-server.argocd.svc.cluster.local:80` |
| `grafana.project101.tech` | `http://monitoring-grafana.monitoring.svc.cluster.local:80` |
| `api.project101.tech` | `http://labs-101-backend.labs-101.svc.cluster.local:8080` (erst beim Umzug) |
| `project101.tech` | `http://labs-101-frontend.labs-101.svc.cluster.local:3000` (erst beim Umzug) |
| `rezepte.project101.tech` | `http://rezepte.rezepte.svc.cluster.local:3000` |
| `notes.project101.tech` | `http://obsidian-web.obsidian-web.svc.cluster.local:4180` (erst beim Umzug) |

Der Management-Port des Backends (9090, `/actuator`) bekommt bewusst keine Route.

## Umzug von labs-101 aus docker compose

labs-101 läuft noch per `docker compose` auf home-server. Die Application `labs-101` synchronisiert deshalb
noch nicht automatisch.

1. `auth.zitadelOrgId` (und ggf. `auth.audience`) in `values/labs-101.yaml` eintragen, Werte wie im
   bisherigen Deployment (GitHub-Secrets `ZITADEL_ORG_ID`, `AUTH_AUDIENCE`).
2. In Argo CD `labs-101` einmal manuell synchronisieren. Es startet mit leerer Datenbank, bekommt aber
   noch keinen Traffic.
3. Wartungsfenster: Backend in docker compose stoppen, Daten übertragen:

   ```sh
   docker stop spring-boot-labs-101
   docker exec postgres-labs-101 pg_dump -U "$POSTGRES_USERNAME" -Fc labs101 > labs101.dump
   kubectl -n labs-101 scale deploy/labs-101-backend --replicas=0
   kubectl -n labs-101 exec -i labs-101-postgres-0 -- \
     pg_restore -U "$POSTGRES_USERNAME" -d labs101 --clean --if-exists --no-owner < labs101.dump
   kubectl -n labs-101 scale deploy/labs-101-backend --replicas=1
   ```

4. Routen `api.project101.tech` und `project101.tech` im Tunnel auf die Services im Cluster umstellen.
5. In `argocd/apps/labs-101.yaml` `automated: {prune: false, selfHeal: true}` setzen.
6. Im App-Repo den Workflow `deployment.yaml` (docker compose) löschen und die Container auf home-server
   stoppen. Den Dump und das Volume erst nach ein paar Tagen ohne Probleme entfernen.

Rückweg bis Schritt 6: Routen zurück auf die compose-Container stellen und `docker start spring-boot-labs-101`.

## Umzug von rezepte aus docker compose

rezepte lief per `docker compose` auf home-server (`~/home/projects/rezepte`, Container `rezepte-app`,
`rezepte-db`), die Bilder lagen auf der Platte unter `public/uploads`.

Erledigt am 2026-11-08 (Dump unter `~/rezepte-umzug` auf home-server). Zum Wiederholen, z. B. wenn in der alten
App danach noch Rezepte dazugekommen sind:

```sh
# Datenbank: die neue App kann laufen, --clean ersetzt die Tabellen. Die Bewertungen gibt es nur in der neuen
# App und hängen an den Rezepten, ohne das DROP scheitert --clean (die App legt die Tabelle beim Start neu an)
docker exec rezepte-db pg_dump -U rezepte -Fc rezepte > rezepte.dump
kubectl -n rezepte exec rezepte-postgres-0 -- psql -U rezepte -d rezepte -c 'DROP TABLE IF EXISTS bewertungen'
kubectl -n rezepte exec -i rezepte-postgres-0 -- \
  pg_restore -U rezepte -d rezepte --clean --if-exists --no-owner --no-acl < rezepte.dump

# Bilder ins Volume rezepte-uploads, die Pfade in der Datenbank bleiben /uploads/<datei>
tar -C ~/home/projects/rezepte/public/uploads --exclude=.gitkeep -cf - . \
  | kubectl -n rezepte exec -i deploy/rezepte -- tar -C /app/public/uploads -xf -
```

Danach die Route `rezepte.project101.tech` im Tunnel auf den Service umstellen und `docker compose down` in
`~/home/projects/rezepte` (das Volume `rezepte_rezepte-daten` erst nach ein paar Tagen löschen).

## Umzug von obsidian-web aus docker compose

obsidian-web läuft noch per `docker compose` auf home-server (`~/home/projects/obsidian-web/deploy`, Container
`deploy-obsidian-web-1` und `deploy-oauth2-proxy-1`, der Tunnel zeigt auf `http://127.0.0.1:4180`). Es gibt keine
Daten zu übertragen: der Vault liegt im Browser und im S3 des Syncs (`s3.project101.tech`).

1. Secret `obsidian-web-secrets` anlegen (oben), Argo CD synchronisiert die Application dann selbst.
2. Prüfen, dass der Pod läuft: `kubectl -n obsidian-web get pods` (2/2 Ready).
3. Route `notes.project101.tech` im Tunnel auf den Service umstellen. Mit demselben Cookie-Secret bleiben die
   Anmeldungen gültig.
4. `docker compose down` in `~/home/projects/obsidian-web/deploy`.

Der Container von obsidian-web lauscht im Pod nur auf `127.0.0.1`, erreichbar ist allein oauth2-proxy: `/__proxy`
ist ein offener Proxy und darf nie ohne Anmeldung davor erreichbar sein.
