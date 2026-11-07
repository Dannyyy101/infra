# cloudflared

Cloudflare Tunnel im Cluster. Cloudflare terminiert TLS und leitet die Anfragen über eine ausgehende
Verbindung an Services im Cluster, es braucht weder offene Ports noch Ingress-Controller oder cert-manager.

## Modi

| `tunnel.mode` | Routen festgelegt in | Secret |
|---|---|---|
| `token` (Standard) | Cloudflare-Dashboard: Zero Trust → Networks → Tunnels → Public Hostnames | `tunnel-token`, Key `token` |
| `config` | `ingress` in den values, also im Git | `tunnel-credentials`, Key `credentials.json` |

## Umstieg vom bisherigen `deploy-cloudflare-tunnel.yaml` ohne Ausfall

Der Chart nutzt standardmäßig das vorhandene Secret `tunnel-token`. Mehrere Connector dürfen gleichzeitig
am selben Tunnel hängen, deshalb zuerst den neuen starten und dann den alten löschen:

```sh
helm upgrade --install tunnel helm/cloudflared -n cloudflare
kubectl -n cloudflare rollout status deploy/tunnel-cloudflared
kubectl -n cloudflare delete deploy cloudflared
```

## Zitadel über den Tunnel

1. Auth-Chart ohne Ingress installieren, TLS macht Cloudflare (die übrigen Standardwerte passen:
   `tlsMode: external`, `externalSecure: true`, `externalPort: 443`):

   ```sh
   helm upgrade --install auth helm/auth -n auth --create-namespace \
     -f helm/auth/values-prod.local.yaml --set ingress.enabled=false
   ```

2. Route anlegen. Im Modus `token` im Dashboard unter Public Hostnames:
   - Subdomain `auth`, Domain `project101.tech`
   - Service: `HTTP` → `auth-zitadel.auth.svc.cluster.local:8085`
   - Additional settings → HTTP Settings → HTTP Host Header: `auth.project101.tech`

   Im Modus `config` dasselbe in den values:

   ```yaml
   ingress:
     - hostname: auth.project101.tech
       service: http://auth-zitadel.auth.svc.cluster.local:8085
       originRequest:
         httpHostHeader: auth.project101.tech
   ```

   Zitadel erkennt die Instanz am Host. Weicht er von `ZITADEL_EXTERNALDOMAIN` ab, antwortet es mit
   „Instance not found“, daher der feste Host Header.

3. Apps verwenden `https://auth.project101.tech` als Issuer (`AUTH_ISSUER`). Auch Backends im Cluster
   gehen über diese öffentliche URL, weil der `iss`-Claim der Tokens genau so lauten muss.

4. Bot Fight Mode für die Zone ausschalten oder für `auth.project101.tech` ausnehmen, sonst kann Cloudflare
   die Server-zu-Server-Anfragen der Backends (JWKS, Userinfo, Token) mit einer Challenge blockieren.

### Einschränkung: natives gRPC

Zum Service im Cluster spricht cloudflared bei `http://` nur HTTP/1.1. Console, Login, OIDC und die
REST-API von Zitadel funktionieren damit, native gRPC-Clients (z. B. das Go-SDK über gRPC) nicht. Wer das
braucht, lässt Zitadel selbst TLS sprechen (`zitadel.tlsMode: enabled` mit einem selbstsignierten
Zertifikat) und setzt in der Route `service: https://…`, `originRequest.http2Origin: true` und
`originRequest.noTLSVerify: true`, außerdem im Dashboard der Zone Network → gRPC einschalten.
