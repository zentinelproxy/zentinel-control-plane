# Authentication

Overview of all authentication and authorization mechanisms in the control plane.

## Web UI (Session Auth)

Browser-based login via `ZentinelCpWeb.Plugs.Auth`.

- Sessions use signed tokens stored in the `user_tokens` table (context: `"session"`)
- Token validation: `ZentinelCp.Accounts.get_user_by_session_token/1`
- Logout clears both the database record and session cookie
- LiveView socket IDs tied to user sessions for real-time updates

Login: `POST /login` with `email` and `password` form fields.
Registration: `POST /register` (or navigate to `/register` in browser).

## API Key Authentication

For operator and CI/CD access to the REST API.

```
Authorization: Bearer <api_key>
```

Plug: `ZentinelCpWeb.Plugs.ApiAuth`

### Key Generation

- 32 bytes of cryptographically random data, Base64-URL encoded
- SHA256 hash stored in DB — raw key shown **once** at creation, cannot be retrieved later
- `key_prefix` (first 8 chars) stored for identification in UI

### Creating an API Key

| Property | Required | Description |
|----------|----------|-------------|
| `name` | Yes | Display name |
| `scopes` | No | Permission scopes (empty = full access) |
| `project_id` | No | Restrict to specific project |
| `expires_at` | No | Auto-expiration date |

### Scopes

| Scope | Access |
|-------|--------|
| `nodes:read` | List nodes, view details, stats |
| `nodes:write` | Register, delete, drift operations |
| `bundles:read` | List, view, download, verify, SBOM |
| `bundles:write` | Create, assign, revoke |
| `rollouts:read` | List, view rollout details |
| `rollouts:write` | Create, pause, resume, cancel, rollback |
| `services:read` | List services, upstreams, certs, etc. |
| `services:write` | Create/update/delete services and related |
| `api_keys:admin` | Create, list, revoke, delete API keys |

Keys with empty scopes have full access (backward compatibility for legacy keys).

### Project Scoping

When a key has `project_id` set, it can only access resources within that project. The `RequireScope` plug validates project match.

### Key Lifecycle

```
Created (active) → Revoked (immediate rejection)
                 → Expired (auto-rejected past expires_at)
                 → Deleted
```

`last_used_at` updated on every successful authentication.

## Node Authentication

Zentinel proxy nodes authenticate using one of two methods:

### Static Node Key

Simple shared secret, suitable for getting started:

```
X-Zentinel-Node-Key: <base64-url-key>
```

- Generated at registration: 32 bytes random data, Base64-URL encoded
- SHA256 hash stored in DB
- Validated by `ZentinelCp.Nodes.Node.valid_node_key?/2`

### JWT Token (Recommended for Production)

Short-lived token exchanged from the static key:

```
Authorization: Bearer <jwt>
```

**Token exchange:**
```bash
curl -X POST http://localhost:4000/api/v1/nodes/:node_id/token \
  -H "X-Zentinel-Node-Key: <node_key>"
```

Response:
```json
{
  "token": "eyJ...",
  "token_type": "Bearer",
  "expires_at": "2026-02-21T19:00:00Z"
}
```

**JWT claims:**

| Claim | Value |
|-------|-------|
| `sub` | Node ID |
| `prj` | Project ID |
| `org` | Organization ID |
| `kid` | Signing key ID |
| `exp` | Expiration (12 hours from issuance) |

**Algorithm:** Ed25519 (EDDSA). Signing keys managed per organization in `signing_keys` table.

**Verification:** `ZentinelCp.Auth.verify_node_token/1` looks up the key by `kid`, verifies signature.

Plug: `ZentinelCpWeb.Plugs.NodeAuth` (accepts both static key and JWT).

## Signing Keys

Ed25519 key pairs for JWT issuance, managed per organization.

- **Create**: Generate new key pair — returns key ID
- **List**: All signing keys (active and inactive)
- **Deactivate**: Mark inactive (existing tokens valid until expiry)
- **Expiration**: Optional `expires_at` for automatic rotation

At least one active signing key must exist when issuing tokens.

## TOTP Multi-Factor Authentication

TOTP-based MFA via `nimble_totp` library. Schema: `ZentinelCp.Accounts.UserTotp`.

1. Generate shared secret + QR code (`otpauth://` URI)
2. User scans with authenticator app, enters verification code
3. 10 single-use recovery codes generated
4. Subsequent logins require TOTP code after password

Managed at `/profile` in the web UI. Recovery codes can be regenerated at any time.

## SSO Integration

### OIDC (OpenID Connect)

Authorization Code with PKCE flow. Controller: `ZentinelCpWeb.Auth.SsoController`.

| Setting | Description |
|---------|-------------|
| `client_id` | OIDC client identifier |
| `client_secret` | Client secret (encrypted at rest) |
| `issuer` | Provider issuer URL |
| `authorize_url` | Authorization endpoint |
| `token_url` | Token exchange endpoint |
| `userinfo_url` | User info endpoint |
| `scopes` | Requested OIDC scopes |
| `group_mapping` | Map IdP groups → org roles |
| `fallback_to_password` | Allow password login as fallback |

### SAML 2.0

Via `samly` library. Config: `ZentinelCp.Auth.SamlProvider`.

| Setting | Description |
|---------|-------------|
| `idp_metadata_url` | IdP metadata URL |
| `idp_sso_url` | SSO endpoint |
| `idp_cert_pem` | IdP signing certificate |
| `sp_entity_id` | Service Provider entity ID |
| `assertion_consumer_service_url` | ACS callback URL |
| `group_mapping` | Map IdP groups → org roles |
| `fallback_to_password` | Allow password login as fallback |

### Just-In-Time Provisioning

On first SSO login:

1. User account created with random password
2. Account marked as confirmed
3. Org membership created with role from group mapping
4. SSO provider type and subject identifier recorded

### Group-to-Role Mapping

```json
{
  "engineering-admins": "admin",
  "engineering": "operator",
  "default": "reader"
}
```

## Rate Limiting

Token-bucket rate limiting on API endpoints.

- **Key**: API key ID (if authenticated) or client IP
- **Scope**: Different limits per endpoint category
- **Headers**: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`
- **429 response**: Returned with `retry_after` value when limit exceeded

Plug: `ZentinelCpWeb.Plugs.RateLimit`.
