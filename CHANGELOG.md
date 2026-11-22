# Changelog

Notable changes to the Zentinel Control Plane. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Upgrade notes

- **The federation tables are dropped.** The migration
  `20261122120000_drop_federation_infrastructure` drops `federation_peers`,
  `regional_storages` and `bundle_replications` with any data in them, removes
  the unused `region`, `region_strategy`, `region_order` and
  `current_region_index` columns from `rollouts`, and deletes queued
  `ZentinelCp.Federation.SyncWorker` jobs. Rolling back recreates the tables
  and columns empty; the data is not restored. No API routes, UI pages or
  permissions are removed, since federation never had any.

### Removed

- Federation (multi-cluster hub and spoke), which was a stub: peers, regional
  storage, bundle replication tracking and the sync job that ran every 60
  seconds without applying anything (#36).

## [0.2.0] - 2026-11-22

The first versioned release. Images are published as
`ghcr.io/zentinelproxy/zentinel-control-plane:0.2.0` and
`ghcr.io/zentinelproxy/zentinel-cp-agent:0.2.0`, with `0.2` tags that follow
the latest patch release. Earlier deployments ran images tagged `main` or by
commit.

### Upgrade notes

Upgrading from a deployment built from `main` before this release changes
how secrets are encrypted, how nodes register and who can reach what. Follow
[Upgrading an Existing Install](docs/DEPLOYMENT.md#upgrading-an-existing-install)
in order. In short:

- **`ENCRYPTION_KEY` is required.** Set it, keep `SECRET_KEY_BASE` unchanged
  until the secrets are re-encrypted with
  `bin/zentinel_cp eval "ZentinelCp.Release.reencrypt_secrets()"`, then rotate
  it if you like.
- **New nodes need a project registration token.** Nodes already registered
  are not affected.
- **Project slugs are unique across all orgs.** Rename duplicates before
  deploying, or the migration fails.
- **`admin@localhost` is no longer created** with a default password. Change
  or delete an existing one. The first admin comes from `ADMIN_EMAIL` and
  `ADMIN_PASSWORD`.
- **SSO users get their mapped role in their org only.** New SSO users are
  global `reader`; review global admins, since existing users keep their role.
- **An API key works only while its owner is a member of the project's org.**
- **Outbound requests to private and local addresses are blocked by default**
  for webhooks and notifications. Health checks, and the Consul, Kubernetes
  and Vault addresses a project configures, may use private networks but not
  loopback or link-local addresses. `ALLOW_PRIVATE_OUTBOUND=true` turns the
  checks off.
- **The control plane's own Kubernetes service account** is used for a
  project's service discovery, or sent to a project's Vault for Kubernetes
  auth, only with `K8S_DISCOVERY_IN_CLUSTER=true` or
  `VAULT_KUBERNETES_IN_CLUSTER_JWT=true`. Without them a project must supply
  its own credentials.
- Audit entries written before this release have only their links verified,
  not their contents.

### Security

- Consul, Kubernetes and Vault addresses a project configures, and a
  project's notification webhook, are checked like other outbound targets.
  These requests do not follow redirects, a failed response is reported by its
  status, and Kubernetes namespace and service names must be valid Kubernetes
  names. (#52)
- Phoenix 1.8.17, Phoenix LiveView 1.2.15 and idna 8.0.0 for published
  advisories. (#51)

### Changed

- The Dockerfiles validate bundles with `ghcr.io/zentinelproxy/zentinel:26.11_4`
  instead of `latest`, so an image built from a release is reproducible.
  Override `ZENTINEL_IMAGE` to use another proxy version.
- The agent image reports the release version (`zentinel-cp-agent --version`)
  instead of the commit.
- `docker-compose.yml` and `agent/docker-compose.example.yml` default to the
  released images instead of `main` and `latest`.

[Unreleased]: https://github.com/zentinelproxy/zentinel-control-plane/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/zentinelproxy/zentinel-control-plane/releases/tag/v0.2.0
