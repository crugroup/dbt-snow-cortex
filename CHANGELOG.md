# Changelog

## 0.3.0 — 2026-10-23

- `create_cortex_search_service` / `apply_cortex_search_config`: new `embedding_model` parameter (default `snowflake-arctic-embed-m-v1.5`, Snowflake's own default), emitted as `EMBEDDING_MODEL = '<model>'`; `none` omits it.
- `create_cortex_search_service` / `apply_cortex_search_config`: new `create_mode` parameter. `replace` (default) keeps today's `CREATE OR REPLACE` on every run; `on_change` skips the statement when the existing service was created from the same definition, so dbt runs no longer rebuild and re-embed the whole index.
- The generated DDL now sets `COMMENT = 'dbt_snow_cortex:def_md5=<hash>'` in both modes.
- `apply_cortex_search_config`: skipped services no longer leave empty statements in the post-hook SQL.

## 0.2.3 — 2026-07-14

- `create_or_replace_semantic_view`: fix first argument to `SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML` — pass 2-part schema name (`db.schema`) instead of 3-part view name (`db.schema.view_name`). The view name is derived from the YAML `name:` field. This fixes Snowflake error 392408 (Unexpected number of qualifiers).

## 0.2.2 — 2026-07-13

- `apply_cortex_search_config`: guard missing graph node with safe get, return early if node not found.

## 0.2.0 — 2026-07-06

- `apply_cortex_search_config`: accept a list of search service configs in `meta.cortex_search`, iterating over each to create all services from a single post-hook. Missing or empty `cortex_search` is now a no-op instead of raising an error, so the same post-hook line can be added safely to any model.
- `create_cortex_search_service`: unchanged (backward compatible).

## 0.1.0 — 2026-05-13

Initial release.

- `create_cortex_search_service`: post-hook macro to create or replace a Snowflake Cortex Search Service on a model table.
- `create_or_replace_semantic_view`: creates (or replaces) a Cortex Analyst semantic view from an inline YAML string.
- `list_cortex_search_services`: run-operation to inspect existing Cortex Search Services.
- `list_semantic_views`: run-operation to inspect existing Cortex Analyst semantic views.
