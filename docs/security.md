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

```elixir
config :zentinel_cp, :bundle_signing,
  enabled: true,
  private_key_path: "/secrets/signing-key.pem",
  public_key_path: "/secrets/signing-key.pub",
  key_id: "key-2024-01"
```

Or inline:
```elixir
config :zentinel_cp, :bundle_signing,
  enabled: true,
  private_key: "base64-encoded-ed25519-private-key",
  public_key: "base64-encoded-ed25519-public-key",
  key_id: "key-2024-01"
```

### Verification

```bash
curl http://localhost:4000/api/v1/projects/my-project/bundles/:id/verify \
  -H "Authorization: Bearer $API_KEY"
```

## Encryption at Rest

All sensitive data encrypted with AES-256-GCM:

| Data | Key Derivation | AAD |
|------|---------------|-----|
| TLS private keys | `secret_key_base` → SHA256 | `"zentinel-cert-key"` |
| Signing keys | `secret_key_base` → SHA256 | `"ZentinelCp.Auth.Encryption"` |
| Secret values | `secret_key_base` → SHA256 | `"zentinel-secret"` |
| ACME account keys | `secret_key_base` → SHA256 | `"zentinel-cert-key"` |

Each value: unique 12-byte IV + 16-byte authentication tag.

## Rate Limiting

Token-bucket rate limiting on API endpoints. See [AUTHENTICATION.md § Rate Limiting](AUTHENTICATION.md#rate-limiting).
