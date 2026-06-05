# @khoralabs/sourcemaps

Licensed under [MIT](LICENSE).

Shared types for **content-addressed source resolution**: a stable ref points at original content, a `Store` materializes it, and consuming code owns locators, projections, and persistence.

Use this library when multiple subsystems need the same ref → resolve contract without sharing domain schemas.

## The pattern

Many systems keep two related artifacts:

1. **Original** — the canonical body (bytes, record, URL target, etc.)
2. **Projection** — something derived for search, fan-out, or UI (indexed text, embeddings, display metadata)

A **source ref** is not the projection. It is the **address** used to find and resolve the original. Projections live elsewhere and are keyed *by* that address, not embedded in the ref type.

```text
  SourceRef (address)              Projection (elsewhere)
  bucket + object_key         -->  search_index.document
  repo + path                 -->  derived_view.snapshot

        Store.resolve(ref)
              |
              v
        ResolvedSource (original materialized)
```

## Types

### Refs (addressing)

| Type | Use when |
|------|----------|
| `SourceRef<Locators>` | You need a stable address; `content_hash` may be absent or filled in later. |
| `ContentAddressedRef<Locators>` | You require a digest on the ref for verify-on-read, provenance, or replication. |
| `ContentHash` | Lowercase SHA-256 hex (64 chars). |
| `isContentAddressedRef(ref)` | Runtime narrow when `content_hash` may be optional on the same locator shape. |

Define **locators** per domain — only fields needed to look up the original:

```ts
type FileLocators = { bucket: string; key: string };
type FileRef = SourceRef<FileLocators> & { content_hash?: ContentHash };

type GitLocators = { repo: string; path: string; revision: string };
type GitPointerRef = ContentAddressedRef<GitLocators>;
```

Do **not** put projection payloads (indexed text, embeddings, UI metadata, etc.) on `SourceRef` / `ContentAddressedRef`.

### Resolution

| Type | Role |
|------|------|
| `Store<Ref, EntityMap>` | `resolve(ref)` → original content as `ResolvedSource`. |
| `ContentAddressedStore<Ref, EntityMap>` | Same contract; ref type requires `content_hash` (stricter call sites). |
| `resolveSourcemap(ref, store)` | Thin helper around `store.resolve`. |
| `ResolvedSource<EntityMap>` | Discriminated union: `string`, `blob`, `url`, `json`, `record`. |
| `ResolvedSourceWire` | JSON-serializable mirror (e.g. JSONL lines); blobs are base64. |
| `EntityMap` | Types **only** the `kind: "record"` branch (`domain` → `value` shape). Not the ref. Not the projection. |

### What does not belong in this package

- Domain validation schemas and storage schemas
- Projection / index rows
- Merge or provenance algorithms

Keep those in the code that owns the domain.

## When to use which ref

**`SourceRef` (optional hash)**

- The ref is created before the body hash is known.
- Resolution is by stable locator only.
- The original may change under the same key; hash is a snapshot, not ref identity.
- Read paths need locators without integrity checks on every access.

**`ContentAddressedRef` (required hash)**

- You verify bytes on read (`sha256(bytes) === ref.content_hash`).
- Replication or fan-out must reject wrong content.
- Provenance treats the hash as part of the contract.

Both can coexist: optional hash on `SourceRef` for flexible lifecycles, required hash on `ContentAddressedRef` for strict paths.

## Implementing a `Store`

1. Pick locator fields → `type MyRef = SourceRef<MyLocators>` or `ContentAddressedRef<MyLocators>`.
2. Implement `Store<MyRef, EntityMap>` (or extend a domain interface that extends it).
3. In `resolve`, return `ResolvedSource` variants; do not return projection rows.

```ts
import type {
  ContentAddressedRef,
  Store,
} from "@khoralabs/sourcemaps";

type ObjectLocators = { bucket: string; key: string };
type ObjectRef = ContentAddressedRef<ObjectLocators>;

export function createObjectStore(/* deps */): Store<ObjectRef> {
  return {
    async resolve(ref) {
      const bytes = await fetchObject(ref.bucket, ref.key);
      // optional: assert sha256(bytes) === ref.content_hash
      return { kind: "blob", blob: new Blob([bytes]) };
    },
  };
}
```

You can extend `Store` with extra methods (sync hooks, batch prefetch, etc.) in your own modules.

## Wire / file-backed caches

JSONL and similar logs should pair domain locators with `ResolvedSourceWire`. That serializes resolved bodies, not projection index state.

Example line shape:

```ts
type CachedLine = SourceRef<{ bucket: string; key: string }> & ResolvedSourceWire;
```

## Tests

```bash
bun test
```

See `src/ref.test.ts` for ref narrowing examples.
