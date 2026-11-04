# Security

## Web Application Firewall

~60 built-in rules based on the OWASP Core Rule Set (CRS).

### Rule Categories

| Category | Rule IDs | Examples |
|----------|----------|---------|
| SQL Injection (`sqli`) | CRS-942xxx | libinjection, tautologies, union-based, blind, stacked, DB-specific |
| XSS (`xss`) | CRS-941xxx | Script tags, event handlers, JS URIs, DOM vectors, encoded payloads |
| Local File Inclusion (`lfi`) | CRS-930xxx | Path traversal, OS file access, null bytes, encoding evasion |
| Remote File Inclusion (`rfi`) | CRS-931xxx | URL params, PHP wrappers, data scheme, off-domain references |
| Remote Code Execution (`rce`) | CRS-932xxx | Unix/Windows injection, PowerShell, shell expressions, Shellshock |
| Scanner Detection (`scanner`) | CRS-913xxx | Vuln scanner UA, scripting/bot UA, missing UA |
| Protocol Violations (`protocol`) | CRS-920xxx | Invalid HTTP, content-type mismatch, URI length, smuggling |
| Data Leak Prevention (`data_leak`) | CRS-950xxx | Credit cards, SSN patterns, SQL errors, stack traces |

Each rule has: severity (`critical`/`high`/`medium`/`low`), phase (`request`/`response`), targets (URI/args/body/headers/cookies), default action.

### WAF Policies

Group rules with project-specific configuration. Attach to services.

| Setting | Options | Description |
|---------|---------|-------------|
| `mode` | `block`, `detect_only`, `challenge` | Block, log-only, or challenge |
| `sensitivity` | `low`, `medium`, `high`, `paranoid` | Overall sensitivity |
| `default_action` | `block`, `log`, `disable` | Default for matched rules |
| `enabled_categories` | Array | Which categories to enable |
| `max_body_size` | Bytes | Max request body to inspect |
| `max_header_size` | Bytes | Max header size to inspect |
| `max_uri_length` | Integer | Max URI length |
| `allowed_content_types` | Array | Restrict content types |

### Rule Overrides

Override individual rule actions per policy. Example: disable a false-positive rule:

```
Rule:    CRS-942100 (SQL Injection - libinjection)
Action:  log         (override from "block")
Note:    "False positive on search queries"
```

### Effective Rule Evaluation

1. Rule override action (if defined in this policy)
2. Policy default action (if no override)
3. Rule default action (fallback)

Rules with `disable` action are skipped. Only rules in `enabled_categories` are evaluated.

### WAF Analytics

- **Event tracking**: Every blocked/logged/challenged request recorded with rule details, client IP, path, matched data
- **Baselines**: Computed hourly over 14-day rolling windows — total blocks, unique IPs, block rates
- **Anomaly detection**: Z-score analysis (>2.5σ) — detects spikes, new attack vectors, IP bursts, rate changes

## Auth Policies

Authentication and authorization policies for services.

| Type | Description |
|------|-------------|
| `jwt` | Validate JWT — issuer, audience, algorithms, JWKS URL |
| `api_key` | Validate API keys from headers or query params |
| `basic` | HTTP Basic Authentication |
| `oauth2` | OAuth 2.0 token introspection |
| `oidc` | OpenID Connect token validation with discovery |
| `custom` | Custom auth with arbitrary config |
| `composite` | Combine multiple policies with AND/OR logic |

Example JWT policy config:
```json
{
  "issuer": "https://auth.example.com",
  "audience": "api.example.com",
  "algorithms": ["RS256", "ES256"],
  "jwks_url": "https://auth.example.com/.well-known/jwks.json"
}
```

Attach to services. Enforced by the Zentinel proxy at request time.

## Bundle Signing

Ed25519 cryptographic signing for bundle integrity and authenticity.

1. Generate Ed25519 key pair
2. During compilation, bundle archive signed with private key
3. Nodes or operators verify against public key
4. Key ID included in signature for rotation support

### Configuration

Set `BUNDLE_SIGNING_ENABLED=true`, `BUNDLE_SIGNING_PRIVATE_KEY_PATH` and `BUNDLE_SIGNING_PUBLIC_KEY_PATH`. See [CONFIGURATION.md](CONFIGURATION.md).

### Verification

```bash
curl http://localhost:4000/api/v1/projects/my-project/bundles/:id/verify \
  -H "Authorization: Bearer $API_KEY"
```

## Encryption at Rest

Sensitive data is encrypted with AES-256-GCM using `ENCRYPTION_KEY`: TLS and ACME private keys, the internal CA key, node signing keys, project secrets, Vault credentials, OIDC client secrets, TOTP secrets, notification channel settings, webhook signing secrets and federation storage keys.

Each value stores the ID of the key that encrypted it, a unique 12-byte IV and a 16-byte authentication tag. Recovery codes and API keys are stored as hashes.

See [DEPLOYMENT.md](DEPLOYMENT.md) to rotate the key.

## Rate Limiting

Token-bucket rate limiting on API endpoints. See [AUTHENTICATION.md § Rate Limiting](AUTHENTICATION.md#rate-limiting).

## Tenant Isolation

- Every LiveView denies access by default. Org and project pages require membership of the org, and the `reader` role cannot make changes.
- An API key can do no more than its owner. Its owner must be a member of the project's org, with at least `operator` for anything beyond `:read` scopes.
- A global admin can reach every org, so grant that role sparingly. SSO cannot grant it.

## Outbound Requests

Webhook and notification URLs must resolve to public addresses. Health check URLs may use private networks but not loopback or link-local addresses, which blocks cloud metadata endpoints. `ALLOW_PRIVATE_OUTBOUND=true` disables these checks. The address is resolved again when the request is sent, so also restrict egress at the network.

## Audit Log

Entries form a hash chain. Verification recomputes each hash, which detects edits, and checks each link, which detects removals. Signed checkpoints detect removal of the newest entries, so create them regularly with `POST /api/v1/audit/checkpoints`.
