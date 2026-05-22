# Contributing

Thanks for contributing to `dbt_snow_cortex`.

## Development setup

Prerequisites:

- dbt Core / dbt Snowflake (same versions supported by this repo)
- A Snowflake account + role that can:
  - `CREATE OR REPLACE CORTEX SEARCH SERVICE`
  - Execute `SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML`
  - Read `INFORMATION_SCHEMA.CORTEX_SEARCH_SERVICES` and `INFORMATION_SCHEMA.SEMANTIC_VIEWS`

Clone and create a branch:

```bash
git clone https://github.com/crugroup/dbt-snow-cortex.git
cd dbt-snow-cortex
git checkout -b my-change
```

## Running integration tests

1. Create a dbt profile named `integration_tests`.

   Use the template at `integration_tests/profiles.yml.example`.
   Copy it to `~/.dbt/profiles.yml` (or pass `--profiles-dir`).

2. Run the example models:

```bash
cd integration_tests
dbt deps
dbt run
```

3. Inspect created services and views:

```bash
dbt run-operation dbt_snow_cortex.list_cortex_search_services \
  --args '{database: YOUR_DATABASE}'

dbt run-operation dbt_snow_cortex.list_semantic_views \
  --args '{database: YOUR_DATABASE}'
```

## Guidelines

- Keep changes focused; avoid drive-by refactors.
- Update `README.md` and `CHANGELOG.md` when behaviour changes.
- Prefer small macros with clear inputs/outputs.
- All macros must use `adapter.dispatch` so that a `default__` variant raises a clear error.

## Submitting a PR

- Include a short description and rationale.
- If you changed DDL generation behaviour, include an example config snippet in the PR description.
