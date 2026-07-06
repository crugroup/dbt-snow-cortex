# Changelog

## 0.2.0 — 2026-07-06

- `apply_cortex_search_config`: accept a list of search service configs in `meta.cortex_search`, iterating over each to create all services from a single post-hook. Missing or empty `cortex_search` is now a no-op instead of raising an error, so the same post-hook line can be added safely to any model.
- `create_cortex_search_service`: unchanged (backward compatible).

## 0.1.0 — 2026-05-13

Initial release.

- `create_cortex_search_service`: post-hook macro to create or replace a Snowflake Cortex Search Service on a model table.
- `create_or_replace_semantic_view`: creates (or replaces) a Cortex Analyst semantic view from an inline YAML string.
- `list_cortex_search_services`: run-operation to inspect existing Cortex Search Services.
- `list_semantic_views`: run-operation to inspect existing Cortex Analyst semantic views.
