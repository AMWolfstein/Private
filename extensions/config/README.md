# Native Rust provider configuration and independent updates

The application now constructs its existing 14 native lyrics providers using the
bundled `providers.json`. All values initially preserve the current endpoints.
No provider algorithm, playback path, preference or UI is replaced by JavaScript.
This is **not the completed artwork/update-system migration**.

## Version 1 capabilities

The document has exactly `schema_version`, `runtime_version`, `revision` and
`lyrics_origins`. It is limited to 64 KiB and requires the complete 12-origin
inventory. All 14 native provider IDs remain supported; several share an origin.

This first schema supports **origin replacement only**. It does not configure
paths, header values, timeouts, provider enablement/order, matching or parsing.
The existing native endpoint adapter preserves request paths and queries.

Only the compiled service origins may appear. Cross-service substitution is
rejected, including sending Apple catalog authorization to another provider.
The two existing LyricsPlus servers may substitute one another; Paxsenix/Zarz
proxy origins may also substitute one another, but the operator must verify that
the destination supports the original request path. All other origins remain
fixed in v1. A new hostname, different path/headers or new service algorithm
still requires a reviewed runtime/schema change and an APK update. Do not claim
this schema can repair every service change.

`schema.json` describes the document. Rust validation is authoritative and also
rejects duplicate keys. No JSON expression is evaluated or downloaded code run.

## Authentication and storage

`trusted-keys.json` is the app-bundled map from key ID to a base64 raw 32-byte
Ed25519 public key. It now contains the initial `release-1` application trust root. Its private
Ed25519 signing key was generated once and remains outside the repository, with
owner-only permissions. Keep a secure operator backup: future configuration
releases require it. The fixture key under `tests/` is never trusted by the app.

An envelope contains exactly `format: 1`, `key_id`, `payload` and `signature`.
Payload and signature use standard base64. The signature covers the bytes
`mornye-provider-config-v1\0` followed by the exact UTF-8 JSON payload bytes.
The whole envelope is limited to 96 KiB. Keys inside a downloaded document can
never authorize themselves.

The native Backend installation method verifies signatures and schema, rejects
non-increasing revisions and writes `.provider_config.json` with a synced
temporary file and atomic replacement. A failed validation/write before replacement
retains the previous cache. No claim is made about power-loss durability of the
parent directory entry. The Backend serializes installs and owns the data directory.

A successful install takes effect at **next Backend initialization**, never in the
middle of a lyrics request. New revisions use their own lyrics persistence file;
old token/coalescing/cache owners are shut down before a new Backend starts.
Corrupt/untrusted caches use bundled defaults and expose a fallback diagnostic
through `provider_configuration_status_json`.

## Operator tooling

Keep the private key outside the checkout, with restricted permissions. For example,
generate an Ed25519 key with OpenSSL, export its raw public key into the reviewed
trust map, and build the app once to establish that trust. Do not use a fixture key.
The operator tool accepts Ed25519 PKCS#8 private keys, including OpenSSL's format.

From the repository root:

```sh
cargo +1.99.1 run --locked --manifest-path rust_backend/Cargo.toml \
  -p mornye-providers --bin provider-config -- validate extensions/config/providers.json
cargo +1.99.1 run --locked --manifest-path rust_backend/Cargo.toml \
  -p mornye-providers --bin provider-config -- \
  sign /path/to/revision-2.json release-key /outside/repo/private.pk8 /tmp/providers.signed.json
cargo +1.99.1 run --locked --manifest-path rust_backend/Cargo.toml \
  -p mornye-providers --bin provider-config -- \
  verify /tmp/providers.signed.json extensions/config/trusted-keys.json
```

The signer refuses to overwrite an existing output. Only the signed JSON and public
key belong in version control; never publish the private key.

## Distribution and remaining work

The owner requested that configuration files live in **AMWolfstein/Private**, under
`extensions/`, on `extension-system`. No upstream repository was modified.
GitHub reported this repository as public during this task, despite its name, so
it can host app-readable files. If it becomes private, raw files cannot serve
unauthenticated updates; do not embed a GitHub token in the APK.

## Automatic updates

After Android has configured allowed directories, network/runtime policy and fallback
providers, its Kotlin owner explicitly starts the backend-owned update worker through
UniFFI. Constructing a Backend alone never starts network requests. Scheduling an
optional update failure cannot prevent local playback.

The only download endpoint is:
`https://raw.githubusercontent.com/AMWolfstein/Private/extension-system/extensions/config/providers.signed.json`.
The repository endpoint was checked anonymously over HTTPS. A private or unavailable
repository cannot serve updates; no GitHub token is embedded in the application.

The worker bounds the envelope to 96 KiB and a 15-second deadline, authenticates it
against the bundled public key, then validates and atomically persists it. Completed
HTTP attempts consume a persisted 24-hour interval. Unavailable-network failures
retry after 15 minutes without waiting for an application restart. Backend shutdown
cancels requests and wakes/joins the owned worker.

The installed revision is **pending restart** until a new Backend initializes.
Rechecking the same stored update preserves that state while the old revision is
active; only the new owner reports it up-to-date. Status JSON retains active_revision,
activation and fallback_reason and adds update.state, candidate_revision and a typed
error. Bad signatures, unsupported settings, failed writes and offline startup keep
bundled/last usable settings. There is no downloaded executable code or hot swap.

To publish a configuration update: increment its revision, validate the complete JSON,
sign it with the private operator key outside Git, verify it against trusted-keys.json,
then review/commit only the JSON/envelope. Never auto-sign or auto-merge unreviewed
upstream changes. A new signing trust root needs an application update.

This completes the independent downloader for schema v1. It still updates **only the
listed lyrics origins**. Native artwork ports, identity resolution/app integration and
a reviewed richer schema remain separate unfinished work; this updater does not make
those JavaScript reference sources active.

All 13 artwork JavaScript references remain inactive and preserved in `../sources/`.
Their native implementations, identity resolution, authentication and parity tests
remain a separate required migration batch. The original native lyrics code and
inactive CommonJS reference ports are retained; nothing has been deleted merely
because a replacement is planned. Jellyfin remains excluded.

## Checks

Run Rust configuration, backend restart and operator CLI tests with:

```sh
cargo +1.99.1 test --locked --manifest-path rust_backend/Cargo.toml -p mornye-providers
cargo +1.99.1 test --locked --manifest-path rust_backend/Cargo.toml -p mornye-extensions
```

These tests cover signature validation, malformed settings, trust boundaries,
failed persistence, restart activation and cache generation separation. They do
not prove live provider availability or Android physical-device behavior.
