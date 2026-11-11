# tsession-dynamodb

Tenant-scoped DynamoDB session persistence for [tsession](https://github.com/jerily/tsession)
2.0.0. Requires Tcl 8.6.14+ and aws-sdk-tcl-dynamodb 1.0.18+.

```tcl
package require tsession-dynamodb 2.0.0
set client [::aws::dynamodb::create {region us-east-1}]
set store [::tsession::dynamodb::create -client $client -table SessionsV2 -tenant my-site]
::tsession::dynamodb::insert $store opaque-id [dict create expires [expr {[clock seconds]+3600}]] user-1
set session [::tsession::dynamodb::get $store opaque-id]
::tsession::dynamodb::update $store opaque-id {preference dark}
::tsession::dynamodb::revoke $store user-1
$client destroy
```

The host owns the client, one per worker. `create` requires `-client`, `-table`
and `-tenant`; it never creates a client or changes schema. Configure signed
cookies separately with `tsession::cookie`. Applications own authentication,
CSRF, token rotation and encryption of sensitive fields. Use unpredictable
browser tokens and store their MACs as IDs; never reuse a session ID.

All operations are in `::tsession::dynamodb`:

| Operation | Behavior |
| --- | --- |
| `insert store id data ?subject?` | Insert a dictionary with integer `expires` (Unix seconds). Duplicate IDs fail. |
| `get store id` | Return data with canonical `id`/`expires`, or `{}` for missing/expired sessions. |
| `update store id changes` | Merge fields using a revision check. Return 1 on success, 0 if missing, expired, revoked or concurrently changed. ID and the revocation subject cannot change. |
| `delete store id` | Delete this tenant's ID; return 1 if present, otherwise 0. |
| `revoke store subject` | Delete this tenant's sessions for a nonempty subject; return the number deleted. |
| `prune store` | Delete this tenant's expired records; return the number deleted. |

Reads are strongly consistent and do not extend expiry. `expires <= clock seconds`
is expired even while DynamoDB TTL deletion is pending. Conditional writes prevent
lost updates and revival of expired/deleted sessions. Service errors propagate;
only conditional conflicts return 0 from update/delete/revoke/prune.

`revoke` and `prune` query all pages for the tenant using the base table, then
conditionally delete matching items. Their cost grows with the tenant's session
count. They are not atomic across sessions; concurrently inserted sessions may
survive revocation. No SQL transactions or global active store are provided.

## Table and migration

Provision [infra/infra.yml](infra/infra.yml) before serving requests. It creates
`SessionsV2` with String partition key `tenant`, String sort key `id`, and TTL
on numeric `expires`. Other attributes are `subject`, `data` and numeric `revision`.
Keys are hex-encoded UTF-8 (tenant: up to 1024 UTF-8 bytes; ID: up to 512).
Subject and serialized Tcl dictionary data are base64-encoded UTF-8; they are
never evaluated as scripts. DynamoDB's item size limit still applies.

Version 2 replaces `tsession::dynamodbstore` and the old `tsession` middleware
integration. The old `Sessions` table with a `session_id` key is incompatible;
deploy the template as a new stack and require users to sign in again. No data migration or
compatibility wrapper is included. The example now uses the explicit store API.

## Install and test

```sh
make install PREFIX=/path/to/prefix
# With dependencies on TCLLIBPATH, against a disposable DynamoDB Local instance:
TSESSION_TEST_DYNAMODB=http://localhost:8000 tclsh tests/all.tcl
```

The integration suite creates and removes a unique table. It uses dummy credentials
and only accepts a loopback HTTP endpoint. Tests cover dictionary persistence,
tenant isolation, expiry, revocation, pagination and concurrent write conflicts.
Without the endpoint, integration tests are skipped.
