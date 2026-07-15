{% macro create_cortex_search_service(
  service_name=none,
  search_column=none,
  primary_key_columns=none,
  attribute_columns=none,
  source_query=none,
  source_query_casts=none,
  warehouse='WAREHOUSE__DBT',
  target_lag='1 hour',
  refresh_mode='INCREMENTAL'
) %}
  {{ return(adapter.dispatch('create_cortex_search_service', 'dbt_snow_cortex')(
    service_name=service_name,
    search_column=search_column,
    primary_key_columns=primary_key_columns,
    attribute_columns=attribute_columns,
    source_query=source_query,
    source_query_casts=source_query_casts,
    warehouse=warehouse,
    target_lag=target_lag,
    refresh_mode=refresh_mode
  )) }}
{% endmacro %}


{% macro snowflake__create_cortex_search_service(
  service_name,
  search_column,
  primary_key_columns,
  attribute_columns,
  source_query,
  source_query_casts,
  warehouse,
  target_lag,
  refresh_mode
) %}
  {#
    Post-hook macro: creates or replaces a Cortex Search Service backed by the
    current model table. Call this from a model's post_hook config block.

    Args:
        service_name:         Fully-qualified service name (DB.SCHEMA.SERVICE_NAME).
                              Defaults to <this.database>.<this.schema>.CSS_<this.identifier>.
        search_column:        VARCHAR column to full-text index (ON clause). Required.
        primary_key_columns:  List of columns for incremental refresh PRIMARY KEY clause.
        attribute_columns:    List of VARCHAR/NUMBER columns exposed as filterable ATTRIBUTES.
        source_query_casts:   Dict of {column_name: sql_type} to cast in the AS SELECT,
                              e.g. {'DATA_DATE': 'VARCHAR'}.
        warehouse:            Virtual warehouse used to build and refresh the service.
        target_lag:           Acceptable staleness, e.g. '1 hour', '30 minutes'.
                              refresh_mode:         INCREMENTAL (default) or FULL.

    Usage in model YAML config:
        config:
          post_hook:
            - "{{ dbt_snow_cortex.create_cortex_search_service(
                    service_name='DB.SCHEMA.CSS_NAME',
                    search_column='MY_TEXT_COL',
                    primary_key_columns=['ID_COL'],
                    attribute_columns=['FILTER_COL'],
                    source_query_casts={'DATE_COL': 'VARCHAR'},
                    warehouse='WAREHOUSE__DBT',
                                          target_lag='1 hour',
                                          refresh_mode='INCREMENTAL') }}"
  #}
{% if search_column is none %}
    {{ exceptions.raise_compiler_error(
      "dbt_snow_cortex.create_cortex_search_service: 'search_column' is required."
    ) }}
{% endif %}

  {% set _service_name = service_name if service_name is not none
    else this.database ~ '.' ~ this.schema ~ '.CSS_' ~ this.identifier %}

{% set _primary_keys = primary_key_columns if primary_key_columns is not none else [] %}
{% set _attributes = attribute_columns if attribute_columns is not none else [] %}
{% set _casts = source_query_casts if source_query_casts is not none else {} %}

  {#
    Build the AS clause.
    When source_query is provided it is used verbatim (supports LATERAL, UNION, subqueries, etc.).
    Otherwise introspect the model relation and build SELECT <cols> FROM {{ this }}.
  #}
{% if source_query is not none %}
    {% set _as_clause = source_query %}
  {% else %}
{% set _source_columns = [] %}
{% for col in adapter.get_columns_in_relation(this) %}
{% if col.name in _casts %}
        {% do _source_columns.append(
          'CAST(' ~ adapter.quote(col.name) ~ ' AS ' ~ _casts[col.name] ~ ') AS ' ~ adapter.quote(col.name)
        ) %}
      {% else %}
        {% do _source_columns.append(adapter.quote(col.name)) %}
      {% endif %}
    {% endfor %}
    {% set _as_clause %}
      SELECT {{ _source_columns | join(', ') }}
      FROM {{ this }}
    {% endset %}
  {% endif %}

  CREATE OR REPLACE CORTEX SEARCH SERVICE {{ _service_name }}
    ON {{ search_column }}
{% if _primary_keys | length > 0 %}
    PRIMARY KEY ({{ _primary_keys | join(', ') }})
    {% endif %}
{% if _attributes | length > 0 %}
    ATTRIBUTES {{ _attributes | join(', ') }}
    {% endif %}
    WAREHOUSE = {{ warehouse }}
    TARGET_LAG = '{{ target_lag }}'
    REFRESH_MODE = {{ refresh_mode }}
  AS (
    {{ _as_clause }}
  )

{% endmacro %}


{% macro default__create_cortex_search_service() %}
{{ exceptions.raise_compiler_error("dbt_snow_cortex only supports Snowflake") }}
{% endmacro %}


{% macro apply_cortex_search_config() %}
  {#
    Zero-argument post_hook companion to create_cortex_search_service.
    Reads Cortex Search parameters from the model's `meta.cortex_search` block.

    When cortex_search contains a list, iterates over each entry to create
    all services from a single post-hook call. When a single dict, creates
    one service (backward compatible).

    Missing or empty cortex_search is a no-op (safe to add to any model).

    Each entry supports:
      service_name:    Short service name (required).
      database:        Target database (default: target.database).
      schema:          Target schema (default: target.schema).
      search_column:   Column to full-text index (required).
      attribute_columns, source_query, source_query_casts, warehouse,
      target_lag, refresh_mode: see create_cortex_search_service.

    Usage in model YAML:
        config:
          meta:
            cortex_search:
              - service_name: CSS_A
                database: MY_DB
                schema: MY_SCHEMA
                search_column: COL_A
                attribute_columns: [X, Y]
              - service_name: CSS_B
                search_column: COL_B
          post_hook:
            - "{{ dbt_snow_cortex.apply_cortex_search_config() }}"
  #}
{% if execute %}
{% do log('dbt_snow_cortex.apply_cortex_search_config: invoked for ' ~ this.unique_id, info=true) %}
{% set cs = config.get('meta', {}).get('cortex_search') %}
{% if cs is none and this.unique_id %}
  {% set node = graph.nodes.get(this.unique_id) %}
  {% if node is not none %}
    {% set cs = node.config.meta.get('cortex_search') %}
  {% endif %}
{% endif %}
{% if cs is none %}
  {% do log('dbt_snow_cortex.apply_cortex_search_config: no cortex_search meta config', info=true) %}
  {% do return('') %}
{% endif %}
{% do log('dbt_snow_cortex.apply_cortex_search_config: found cortex_search config', info=true) %}

{# Normalise single dict or list to list #}
{% if cs is mapping %}
  {% set configs = [cs] %}
{% else %}
  {% set configs = cs %}
{% endif %}

{% set statements = [] %}

{% do log('dbt_snow_cortex.apply_cortex_search_config: creating ' ~ configs | length ~ ' search service(s) for ' ~ this.unique_id, info=true) %}

{% for config in configs %}
  {% set _database = config.get('database', this.database) %}
  {% set _schema = config.get('schema', this.schema) %}
  {% set _service_name = config.get('service_name') %}
  {% if _service_name is none %}
    {% set _service_name = this.identifier %}
  {% endif %}
  {% set _q_db = adapter.quote(_database) %}
  {% set _q_sch = adapter.quote(_schema) %}
  {% set _q_name = adapter.quote(_service_name) %}
  {% set _full_name = _q_db ~ '.' ~ _q_sch ~ '.' ~ _q_name %}

  {% do run_query('CREATE SCHEMA IF NOT EXISTS ' ~ _q_db ~ '.' ~ _q_sch) %}

  {% do statements.append(
    dbt_snow_cortex.create_cortex_search_service(
      service_name=_full_name,
      search_column=config.get('search_column'),
      primary_key_columns=config.get('primary_key_columns', []),
      attribute_columns=config.get('attribute_columns', []),
      source_query=config.get('source_query'),
      source_query_casts=config.get('source_query_casts', {}),
      warehouse=config.get('warehouse', 'WAREHOUSE__DBT'),
      target_lag=config.get('target_lag', '1 hour'),
      refresh_mode=config.get('refresh_mode', 'INCREMENTAL')
    )
  ) %}
{% endfor %}

{{ return(statements | first) }}
{% endif %}
{% endmacro %}
