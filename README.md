# dbt_snow_cortex

`dbt_snow_cortex` is a shared dbt package that manages Snowflake Cortex objects from dbt:

- Cortex Search Services (for RAG/search use cases)
- Cortex Analyst semantic view deployment (from YAML)
- Operational listing and verification macros for runtime checks

This package is intended to be reused across data products as a common Cortex layer.

## Compatibility

- Platform: Snowflake only
- dbt-core: `>=1.9.0, <3.0.0`

## What This Package Provides

### Search service deployment

- `create_cortex_search_service`: create/replace search service from a model post-hook (direct call)
- `apply_cortex_search_config`: zero-arg post-hook that reads `config.meta.cortex_search` (preferred)

### Semantic view deployment

- `create_or_replace_semantic_view`: deploy semantic view from inline YAML content
- `semantic-view-yaml-sync` pre-commit hook: keep source YAML and inline macro payload in sync

### Operations / verification

- `list_cortex_search_services`
- `list_semantic_views`
- `get_cortex_search_services` (returns result set)
- `get_semantic_views` (returns result set)
- `collect_cortex_deployment_status` (returns found/missing object sets)
- `log_cortex_deployment_summary` (standardized deployment logging)
- `assert_cortex_deployment` (optional fail-on-missing assertion)

## Installation

Add the package to your product repo and run `dbt deps`.

Local path (recommended for local development):

```yaml
packages:
  - local: ../../dbt-snow-cortex
```

Git reference:

```yaml
packages:
  - git: "https://github.com/crugroup/dbt-snow-cortex.git"
    revision: 0.1.0
```

## Required Snowflake Privileges

The executing role needs privileges to:

- `CREATE OR REPLACE CORTEX SEARCH SERVICE`
- execute `SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML`
- read `INFORMATION_SCHEMA.CORTEX_SEARCH_SERVICES`
- read `INFORMATION_SCHEMA.SEMANTIC_VIEWS`

## Key Usage Patterns

### 1) Model post-hook for Cortex Search Service (preferred)

Declare services via `meta.cortex_search` as a list. The same post-hook line
works on any model — models without `cortex_search` are silently skipped.

```yaml
models:
  - name: mart_example
    config:
      meta:
        cortex_search:
          - service_name: CSS_PRODUCT_SEARCH
            database: ANALYTICS_DB
            schema: CORTEX
            search_column: DESCRIPTION
            primary_key_columns: [RECORD_ID, EVENT_DATE]
            attribute_columns: [COUNTRY, CATEGORY]
            source_query_casts: {EVENT_DATE: VARCHAR}
            embedding_model: snowflake-arctic-embed-l-v2.0
            create_mode: on_change
          - service_name: CSS_PRODUCT_META
            search_column: PRODUCT_NAME
            attribute_columns: [CATEGORY, PRICE_BAND]
      post_hook:
        - "{{ dbt_snow_cortex.apply_cortex_search_config() }}"
```

### 2) Direct `create_cortex_search_service` call (alternative)

For cases where the meta-based config is not suitable, call
`create_cortex_search_service` directly in the post_hook:

```yaml
models:
  - name: mart_example_records
    config:
      post_hook:
        - "{{ dbt_snow_cortex.create_cortex_search_service(
                service_name='ANALYTICS_DB.CORTEX.CSS_PRODUCT_SEARCH',
                search_column='DESCRIPTION',
                primary_key_columns=['RECORD_ID', 'EVENT_DATE'],
                attribute_columns=['RECORD_ID', 'COUNTRY', 'CATEGORY'],
                source_query_casts={'EVENT_DATE': 'VARCHAR'},
                warehouse='COMPUTE_WH',
                target_lag='1 hour',
                refresh_mode='INCREMENTAL',
                embedding_model='snowflake-arctic-embed-l-v2.0',
                create_mode='on_change') }}"
```

### 3) Semantic view deployment from YAML (run-operation)

Use for deterministic one-off or release-time deployment.

```bash
dbt run-operation dbt_snow_cortex.create_or_replace_semantic_view \
  --args '{
    view_name: PRODUCT_ANALYST,
    database: ANALYTICS_DB,
    schema: CORTEX,
    replace: true,
    yaml_content: "name: PRODUCT_ANALYST\ntables: []"
  }'
```

### 3a) Generic semantic YAML sync (pre-commit / CI)

This package ships a reusable pre-commit hook that generates or validates inline
semantic-view payload macros from a YAML source file.

Example in a consumer repository:

```yaml
repos:
  - repo: ../../dbt-snow-cortex
    rev: HEAD
    hooks:
      - id: semantic-view-yaml-sync
        args:
          - --yaml-path
          - dbt/semantic_views/semantic_view_asset_platform.yaml
          - --macro-path
          - dbt/macros/semantic_view_asset_platform_yaml.sql
          - --macro-name
          - asset_platform_semantic_view_yaml
```

For CI drift checks, append `--check` to the hook args.

### 4) Runtime inspection commands

```bash
dbt run-operation dbt_snow_cortex.list_cortex_search_services \
  --args '{database: ANALYTICS_DB, schema: CORTEX}'

dbt run-operation dbt_snow_cortex.list_semantic_views \
  --args '{database: ANALYTICS_DB, schema: CORTEX}'
```

### 5) Common deployment logging for orchestrators

Use this macro to emit a consistent summary in dbt logs, then let your orchestrator
(Airflow, etc.) handle notification routing.

```bash
dbt run-operation dbt_snow_cortex.log_cortex_deployment_summary \
  --args '{
    database: ANALYTICS_DB,
    schema: CORTEX,
    expected_search_services: [CSS_PRODUCT_SEARCH, CSS_MART_EXAMPLE],
    expected_semantic_views: [PRODUCT_ANALYST]
  }'
```

### 6) Common deployment assertion for post-deploy checks

Use this macro when pipelines should fail if expected Cortex objects are missing.

```bash
dbt run-operation dbt_snow_cortex.assert_cortex_deployment \
  --args '{
    database: ANALYTICS_DB,
    schema: CORTEX,
    expected_search_services: [CSS_PRODUCT_SEARCH, CSS_MART_EXAMPLE],
    expected_semantic_views: [PRODUCT_ANALYST],
    fail_if_missing: true
  }'
```

## Macro Parameters

### `create_cortex_search_service`

| Parameter | Required | Default | Notes |
|---|---|---|---|
| `service_name` | Yes | model identifier | Short service name within the schema |
| `database` | No | `target.database` | Database for the service |
| `schema` | No | `target.schema` | Schema for the service |
| `search_column` | Yes | n/a | Column used in `ON` clause |
| `primary_key_columns` | No | `[]` | For incremental refresh primary key |
| `attribute_columns` | No | `[]` | Filterable attributes |
| `source_query` | No | auto-built from relation | Use custom SQL when you need unions/lateral/subqueries |
| `source_query_casts` | No | `{}` | Column cast map when using auto-built source query |
| `warehouse` | No | `COMPUTE_WH` | Build/refresh warehouse |
| `target_lag` | No | `1 hour` | Staleness target |
| `refresh_mode` | No | `INCREMENTAL` | `INCREMENTAL` or `FULL` |
| `embedding_model` | No | `snowflake-arctic-embed-m-v1.5` | Cortex embedding model, e.g. `snowflake-arctic-embed-l-v2.0`; `none` omits `EMBEDDING_MODEL` from the DDL |
| `create_mode` | No | `replace` | `replace`: `CREATE OR REPLACE` on every run. `on_change`: skip when the service's definition is unchanged (see below) |

#### `create_mode: on_change`

`CREATE OR REPLACE` rebuilds the service from scratch, re-embedding every row and dropping its
grants. With `create_mode: on_change` the macro fingerprints the rendered definition (MD5 over
the name, `ON`/`PRIMARY KEY`/`ATTRIBUTES`/warehouse/lag/model/refresh clauses and the source
query), stores it in the service `COMMENT` as `dbt_snow_cortex:def_md5=<hash>`, and on later runs
returns no SQL when the existing service carries the same hash. Row changes in the source are
then picked up by the service's own incremental refresh (`TARGET_LAG`); only a definition change
triggers a rebuild. Re-apply grants in a later post-hook so they survive a rebuild.

### `create_or_replace_semantic_view`

| Parameter | Required | Default | Notes |
|---|---|---|---|
| `view_name` | Yes | n/a | Semantic view name |
| `yaml_content` | Yes | n/a | Inline YAML text |
| `yaml_file_path` | No | `none` | Reserved for backward compatibility |
| `database` | No | `target.database` | Target database |
| `schema` | No | `CORTEX_ANALYST` | Target schema |
| `replace` | No | `true` | If false, existing view is left unchanged |
| `create_mode` | No | `on_change` | `on_change`: skip when the view's YAML is unchanged (see below). `replace`: recreate on every run |

#### `create_mode: on_change`

With the default `create_mode: on_change` the macro fingerprints the view (MD5 over the
fully-qualified name and the YAML), appends it to the view `COMMENT` as
`[dbt_snow_cortex:def_md5=<hash>]` after the YAML `description`, and on later runs skips the
`CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML` when the existing view carries the same hash. Views
created before this marker existed are recreated once on the next run, then skipped while
unchanged. Pass `create_mode='replace'` to recreate on every run.

## Integration Tests

```bash
cd integration_tests
dbt deps
dbt run
```

Profile template: `integration_tests/profiles.yml.example`

## Operational Notes for Data Products

- Keep semantic YAML human-readable in your product repo and pass it inline to this package macro.
- Prefer YAML-as-source-of-truth and generate inline macro payloads using the sync hook.
- Prefer explicit, fully-qualified object names in production (`DB.SCHEMA.OBJECT`).
- Use dedicated compute warehouse for Cortex objects to avoid contention with transformation runs.
- Run listing macros in post-deploy checks (or orchestrator validation tasks).

## Debugging

- Set `DBT_LOG_LEVEL=debug` to inspect generated SQL and macro execution.
- Check `logs/dbt.log` in your product repo for operational traces.

## Resources

- [Snowflake Cortex Search](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview)
- [Snowflake Cortex Analyst](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst)
