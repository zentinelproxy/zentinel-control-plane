# Security

This guide covers the security features of Sentinel Control Plane, including the Web Application Firewall, authentication policies, certificate management, bundle signing, API key management, and SSO.

## Web Application Firewall

The WAF protects services from common web attacks using a rule-based detection engine inspired by the OWASP Core Rule Set (CRS).

### WAF Rules

The control plane ships with approximately 60 built-in rules covering:

| Category | Rule IDs | Examples |
|----------|----------|---------|
| SQL Injection (`sqli`) | CRS-942xxx | libinjection detection, tautologies, union-based, blind, stacked queries, DB-specific |
| Cross-Site Scripting (`xss`) | CRS-941xxx | Script tags, event handlers, JavaScript URIs, DOM vectors, encoded payloads |
| Local File Inclusion (`lfi`) | CRS-930xxx | Path traversal, OS file access, null bytes, encoding evasion |
| Remote File Inclusion (`rfi`) | CRS-931xxx | URL parameters, PHP wrappers, data scheme, off-domain references |
| Remote Code Execution (`rce`) | CRS-932xxx | Unix/Windows command injection, PowerShell, shell expressions, Shellshock |
| Scanner Detection (`scanner`) | CRS-913xxx | Vulnerability scanner UA, scripting/bot UA, missing UA |
| Protocol Violations (`protocol`) | CRS-920xxx | Invalid HTTP lines, content-type mismatch, URI length, HTTP smuggling |
| Data Leak Prevention (`data_leak`) | CRS-950xxx | Credit card numbers, SSN patterns, SQL error messages, stack traces |

Each rule has a severity (`critical`, `high`, `medium`, `low`), a phase (`request` or `response`), targets (URI, args, body, headers, cookies), and a default action.

### WAF Policies

WAF policies group rules with project-specific configuration. Attach a policy to one or more services.

**Policy settings**:

| Setting | Options | Description |
|---------|---------|-------------|
| `mode` | `block`, `detect_only`, `challenge` | Whether to block, log-only, or challenge |
| `sensitivity` | `low`, `medium`, `high`, `paranoid` | Overall sensitivity level |
| `default_action` | `block`, `log`, `disable` | Default action for matched rules |
| `enabled_categories` | Array of category slugs | Which rule categories to enable |
| `max_body_size` | Integer (bytes) | Maximum request body size to inspect |
| `max_header_size` | Integer (bytes) | Maximum header size to inspect |
| `max_uri_length` | Integer | Maximum URI length |
| `allowed_content_types` | Array of MIME types | Restrict allowed content types |

### Rule Overrides

Override the action for individual rules within a policy. For example, disable a specific SQL injection rule that causes false positives for your application:

```
Rule:    CRS-942100 (SQL Injection - libinjection)
Action:  log         (override from default "block")
Note:    "False positive on search queries"
```

### Effective Rules

The WAF evaluates rules in priority order:

1. **Rule override action** (if defined for this rule in this policy)
2. **Policy default action** (if no override)
3. **Rule default action** (fallback)

Rules with action `disable` are excluded entirely. Only rules in the policy's `enabled_categories` are evaluated.

### WAF Analytics

WAF events are collected from nodes and analyzed:

- **Event tracking**: Every blocked/logged/challenged request is recorded with rule details, client IP, path, and matched data
- **Statistical baselines**: Computed hourly over 14-day rolling windows for total blocks, unique IPs, and block rates
- **Anomaly detection**: Z-score analysis detects spikes (>2.5 standard deviations), new attack vectors, IP bursts, and rate changes

See [Observability > WAF Analytics](observability.md#waf-analytics) for dashboard details.

## Auth Policies

Auth policies define how services verify client identity and authorization.

### Policy Types

| Type | Description |
|------|-------------|
| `jwt` | Validate JWT tokens — configure issuer, audience, algorithms, JWKS URL |
| `api_key` | Validate API keys from headers or query parameters |
| `basic` | HTTP Basic Authentication against configured credentials |
| `oauth2` | OAuth 2.0 token introspection endpoint |
| `oidc` | OpenID Connect token validation with discovery |
| `custom` | Custom authentication with arbitrary configuration |
| `composite` | Combine multiple policies with AND/OR logic |

### Attaching to Services

Assign an auth policy to a service to enforce authentication on all requests matching that service's route path. The policy is evaluated by the Sentinel proxy at request time.

## Bundle Signing

Bundles can be cryptographically signed to ensure integrity and authenticity.

### How It Works

1. **Key generation**: Generate an Ed25519 key pair
2. **Signing**: During compilation, the bundle archive is signed with the private key
3. **Verification**: Nodes (or operators) can verify the signature against the public key
4. **Key ID**: Each signature includes a key identifier for key rotation support

### Configuration

Enable signing by setting the following environment variables or configuration:

```elixir
config :sentinel_cp, :bundle_signing,
  enabled: true,
  private_key: "base64-encoded-ed25519-private-key",
  public_key: "base64-encoded-ed25519-public-key",
  key_id: "key-2024-01"
```

Or use file paths:

```elixir
config :sentinel_cp, :bundle_signing,
  enabled: true,
  private_key_path: "/secrets/signing-key.pem",
  public_key_path: "/secrets/signing-key.pub",
  key_id: "key-2024-01"
```

### Verifying a Bundle

```bash
curl http://localhost:4000/api/v1/projects/my-project/bundles/:id/verify \
  -H "Authorization: Bearer YOUR_API_KEY"
```

Returns whether the signature is valid and which key was used.

## Signing Keys (JWT)

Signing keys are Ed25519 key pairs used to issue JWT tokens for node authentication. They are managed per organization.

### Key Management

- **Create**: Generate a new key pair — returns the key ID
- **List**: View all signing keys for an org (active and inactive)
- **Deactivate**: Mark a key as inactive (tokens signed with it can still be verified until they expire)
- **Expiration**: Keys can have an optional `expires_at` date for automatic rotation

The control plane ensures at least one active signing key exists when issuing tokens.

### Node JWT Tokens

Nodes can exchange their static node key for a short-lived JWT (default: 12 hours):

```
POST /api/v1/nodes/:node_id/token
Header: X-Sentinel-Node-Key: <node_key>
```

The JWT contains:
- `sub`: Node ID
- `prj`: Project ID
- `org`: Organization ID
- `kid`: Key ID (for key lookup during verification)
- `exp`: Expiration (12 hours from issuance)

Nodes then use `Authorization: Bearer <jwt>` for all subsequent API calls.

See [Node Management > Authentication](node-management.md#authentication) for the full authentication flow.

## API Key Management

API keys authenticate operators and CI/CD systems with the control plane REST API.

### Creating an API Key

| Property | Description |
|----------|-------------|
| `name` | Display name for identification |
| `scopes` | Permission scopes (empty = full access for backward compatibility) |
| `project_id` | Optional — restrict to a specific project |
| `expires_at` | Optional expiration date |

The raw API key is returned **once** at creation and cannot be retrieved later. A `key_prefix` (first 8 characters) is stored for identification in the UI.

### Scopes

| Scope | Description |
|-------|-------------|
| `nodes:read` | List and view nodes |
| `nodes:write` | Register and manage nodes |
| `bundles:read` | List, view, and download bundles |
| `bundles:write` | Create, assign, and revoke bundles |
| `rollouts:read` | List and view rollouts |
| `rollouts:write` | Create and control rollouts |
| `services:read` | List and view services and related resources |
| `services:write` | Create and manage services |
| `api_keys:admin` | Manage API keys |

Legacy API keys with empty scopes retain full access for backward compatibility.

### Project Scoping

When an API key has a `project_id`, it can only access resources within that project. The scope enforcement plug validates that the requested project matches the API key's project.

### Key Lifecycle

```
Created (active) → Revoked → Deleted
                 → Expired (automatic)
```

- **last_used_at**: Updated on every successful authentication
- **Revocation**: Immediate — revoked keys are rejected on next use
- **Expiration**: Keys past their `expires_at` date are automatically rejected

## SSO Integration

The control plane supports enterprise Single Sign-On via OIDC and SAML.

### OIDC (OpenID Connect)

Configure an OIDC provider for your organization:

| Setting | Description |
|---------|-------------|
| `client_id` | OIDC client identifier |
| `client_secret` | OIDC client secret (encrypted at rest) |
| `issuer` | Provider issuer URL |
| `authorize_url` | Authorization endpoint |
| `token_url` | Token exchange endpoint |
| `userinfo_url` | User info endpoint |
| `scopes` | Requested OIDC scopes |
| `group_mapping` | Map IdP groups to org roles |
| `fallback_to_password` | Allow password login as fallback |

The flow uses Authorization Code with PKCE for security.

### SAML 2.0

Configure a SAML provider:

| Setting | Description |
|---------|-------------|
| `idp_metadata_url` | IdP metadata URL |
| `idp_sso_url` | SSO endpoint |
| `idp_cert_pem` | IdP signing certificate |
| `sp_entity_id` | Service Provider entity ID |
| `assertion_consumer_service_url` | ACS callback URL |
| `group_mapping` | Map IdP groups to org roles |
| `fallback_to_password` | Allow password login as fallback |

### Just-In-Time Provisioning

When a user authenticates via SSO for the first time:

1. A user account is automatically created with a random password
2. The account is marked as confirmed
3. An org membership is created with a role derived from IdP group mapping
4. SSO provider type and subject identifier are recorded

### Group-to-Role Mapping

Map IdP groups to organization roles:

```json
{
  "engineering-admins": "admin",
  "engineering": "operator",
  "default": "reader"
}
```

## TOTP Multi-Factor Authentication

Users can enable TOTP-based MFA:

1. Generate a shared secret and display the QR code (`otpauth://` URI)
2. User scans with their authenticator app and enters a verification code
3. 10 recovery codes are generated for backup access
4. Subsequent logins require a TOTP code after password verification

Recovery codes are single-use. Users can regenerate recovery codes at any time.

## Encryption at Rest

Sensitive data is encrypted at rest using AES-256-GCM:

| Data | Encryption Key Source |
|------|----------------------|
| TLS private keys | `secret_key_base` → SHA256 (AAD: "sentinel-cert-key") |
| Signing keys | `secret_key_base` → SHA256 (AAD: "SentinelCp.Auth.Encryption") |
| Secret values | `secret_key_base` → SHA256 (AAD: "sentinel-secret") |
| ACME account keys | `secret_key_base` → SHA256 (AAD: "sentinel-cert-key") |

Each encrypted value includes a unique 12-byte IV and 16-byte authentication tag for integrity verification.

## Rate Limiting

API endpoints are protected by token-bucket rate limiting:

- **Rate limit key**: API key ID (if authenticated) or client IP
- **Scope-based limits**: Different limits for different endpoint categories
- **Response headers**: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`
- **429 response**: Returned when rate limit exceeded, with `retry_after` value
