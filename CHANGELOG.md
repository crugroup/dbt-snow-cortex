# Changelog

## 0.5.1 — 2026-11-09

- `create_cortex_search_service` / `apply_cortex_search_config`: new `distinct` parameter, default `false`. The auto-built source query no longer uses `SELECT DISTINCT` unless `distinct=true`. This changes the definition hash, so existing services built from the auto-built query are rebuilt once on the next run; pass `distinct=true` to keep the old query and hash. Services using `source_query` are unaffected.

## 0.5.0 — 2026-11-09

- **Breaking:** semantic view support removed; the package now manages Cortex Search Services only. Removed `create_or_replace_semantic_view`, `list_semantic_views`, `get_semantic_views`, the `expected_semantic_views` argument of `collect_cortex_deployment_status` / `log_cortex_deployment_summary` / `assert_cortex_deployment` (and the `*_semantic_views` keys of the returned status), and the `semantic-view-yaml-sync` pre-commit hook.
- `create_cortex_search_service` / `apply_cortex_search_config`: new `other_columns` parameter (default `[]`) for columns included in the auto-built source query, and so returnable in search results, without being the search column or `ATTRIBUTES`. `source_query_casts` applies to them; ignored when `source_query` is given. Existing services without `other_columns` keep their definition hash and are not rebuilt.

## 0.4.1 — 2026-10-26

- `create_cortex_search_service` / `apply_cortex_search_config`: `create_mode` now defaults to `on_change`, matching `create_or_replace_semantic_view`. Services created by 0.3.0+ already carry the definition hash and are skipped while unchanged; older services are rebuilt once. Pass `create_mode='replace'` to rebuild on every run as before.

## 0.4.0 — 2026-10-23

- `create_or_replace_semantic_view`: new `create_mode` parameter, defaulting to `on_change`: the view is only recreated when its YAML changes, tracked by a `[dbt_snow_cortex:def_md5=<hash>]` marker appended to the view `COMMENT`. Existing views are recreated once on the first run after upgrading. Pass `create_mode='replace'` to recreate on every run as before.

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
