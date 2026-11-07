# Hush Sync protocol (v1)

Hush can optionally sync with a self-hosted `hush-server`. This document is the
contract between any Hush client (iPhone today; Android or desktop later) and the server.
Everything a client needs to read and write the same data is here.

The server is a dumb, encrypted mailbox. It never sees plaintext, never sees the
passphrase or key, and doesn't know what kind of item a record is.

## Connection

* Base URL, for example `https://hush.example-tailnet.ts.net` or `http://192.168.1.20:8080`.
* Every request except `/v1/health` needs `Authorization: Bearer <token>`. The token is
  printed in the server log on first start (`docker compose logs hush`) and can be shown again with
  `docker compose exec hush /hush-server token`.
* JSON bodies are UTF-8. Errors look like `{"error": "message"}`.

## Key

1. On first setup a client creates a random 16-byte `salt` and asks the user for a passphrase.
2. `key = PBKDF2-HMAC-SHA256(NFC(passphrase), salt, iterations = 600000, length = 32)`.
3. The client stores `{salt, iterations, check}` on the server with `PUT /v1/vault`, where
   `check = seal("hush-sync-check-v1", context: "vault")`.
4. Other clients `GET /v1/vault`, derive the key the same way and confirm it by opening `check`.

## Encryption

`seal(plaintext, context)` is AES-256-GCM with a random 12-byte nonce and the UTF-8 bytes
of `context` as associated data. Output is `nonce (12) || ciphertext || tag (16)`.
In JSON it is base64 (standard alphabet, padded).

| Thing | context |
| --- | --- |
| passphrase check | `vault` |
| record with id X | `record:X` |
| blob with id B | `blob:B` |

Binding the id means the server can't swap one record's contents for another's.

## Records

Every item (note, task, habit, device, …) is one record. The record id is the item's UUID in
uppercase canonical form, for example `0F8E4C1A-2B3D-4E5F-8A9B-0C1D2E3F4A5B`.

The record's `data` is `base64(seal(envelope_json, "record:" + id))` where:

```json
{
  "v": 1,
  "type": "note",
  "id": "0F8E4C1A-…",
  "modifiedAt": 1731000000.5,
  "fields": { "title": "Homelab notes", "body": "…", "tags": ["homelab"], "updatedAt": 1731000000.5, "folderID": null }
}
```

### Field encodings

| Kind | JSON |
| --- | --- |
| text | string |
| whole number | number |
| decimal | number |
| yes/no | boolean |
| date | number, seconds since 1970-01-01 UTC (may be fractional) |
| id reference | uppercase UUID string, or `null` |
| list of text / ids | array of strings |
| small binary (`…Data` fields) | base64 string; these hold UTF-8 JSON (subtasks, habit logs, board columns, …) |
| attachment | `{"blob": "<blob id>"}`, `""` for empty, or `null` |

Fields missing from a record keep their current value; unknown fields must be ignored, and
unknown `type`s must be skipped (not deleted). Field names match the app's model properties;
`Hush/Sync/SyncModels.generated.swift` lists every type and field.

### Types

`note`, `task`, `event`, `journal`, `drawing`, `vault`, `file`, `contact`, `bookmark`, `folder`,
`noteVersion`, `template`, `habit`, `board`, `boardCard`, `labDevice`, `labService`, `labSubnet`,
`labRack`, `labLink`, `labDiagram`, `runbook`, `composeStack`.

Items in the Trash are ordinary records with `deletedAt` set. Records that are gone for good
are tombstones (`deleted: true`).

## Blobs (attachments)

Photos, files, drawings and memos are uploaded separately:

* Blob id: `"b" + base64url_nopad(HMAC-SHA256(key, "blob:" + hex_sha256(plaintext)))[0..<40]`.
  The same content always gets the same id, and the id says nothing without the key.
* Body: `seal(plaintext, "blob:" + id)`, raw bytes (not base64).
* Upload a record's blobs before pushing the record.

## Endpoints

| Method and path | Purpose |
| --- | --- |
| `GET /v1/health` | `{"ok": true, "version": "1.0.0", "protocol": 1}` (no token needed) |
| `GET /v1/vault` | `{"initialized": false}` or `{"initialized": true, "salt", "iterations", "check"}` |
| `PUT /v1/vault` | set `{salt, iterations, check}`; 409 if already set (add `?replace=1` to change it) |
| `DELETE /v1/vault?confirm=erase` | delete every record, blob and the passphrase check |
| `GET /v1/stats` | counts: `records`, `deleted`, `head`, `blobs`, `blobBytes`, `version` |
| `POST /v1/push` | upload changes (below) |
| `GET /v1/pull?since=N&limit=500` | changes after sequence N |
| `PUT/GET/HEAD/DELETE /v1/blobs/{id}` | attachments |

### Sequence numbers

Each accepted write gets the next number from a server-wide counter (`seq`). A client remembers the
highest `seq` it has pulled and the `seq` of each record as it last saw it.

### Push

```json
{"records": [
  {"id": "…", "base": 41, "data": "…"},
  {"id": "…", "base": 17, "deleted": true}
]}
```

`base` is the record's `seq` as the client last saw it (0 for new). If the server's copy has a
different `seq`, the write is rejected and the current copy is returned so the client can merge:

```json
{"head": 52, "results": [
  {"id": "…", "ok": true, "seq": 52},
  {"id": "…", "current": {"id": "…", "seq": 44, "deleted": false, "data": "…"}}
]}
```

`"force": true` skips the check. At most 1000 records per push.

### Pull

`{"records": [{"id", "seq", "deleted", "data"}], "seq": <last seq returned>, "head": <server head>, "more": bool}`
in ascending `seq`. Keep calling with `since = seq` while `more` is true.

## Client algorithm (what Hush does)

1. **Pull** everything after the saved position. For each record:
   * if it is the version this client already has, skip it;
   * if the item wasn't changed here since the last sync, apply it (or delete it for a tombstone);
   * if it was changed on both sides, the newer `updatedAt` wins (the server copy wins for items
     without one). A losing note is kept as a `noteVersion`, so no text is lost. A local edit
     beats a remote delete.
2. **Push** every item whose encoded fields changed since the last sync, plus tombstones for
   items deleted here. Merge any conflicts as in step 1 and retry once.
3. Delete blobs this client uploaded that no item uses any more.

Change detection compares SHA-256 of the canonical (key-sorted) fields JSON with the value saved
after the last sync.
