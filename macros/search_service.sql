{% macro create_cortex_search_service(
  service_name=none,
  search_column=none,
  primary_key_columns=none,
  attribute_columns=none,
  source_query=none,
  source_query_casts=none,
  warehouse='COMPUTE_WH',
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
    Reads all Cortex Search parameters from the model's `meta.cortex_search` block,
    so the hook call in YAML is a single clean line.

    Usage in model YAML:
        config:
          meta:
            cortex_search:
              service_name: 'DB.SCHEMA.CSS_NAME'
              search_column: 'MY_TEXT_COL'
              primary_key_columns: [ID]
              attribute_columns: [A, B]
              source_query_casts: {DATE_COL: VARCHAR}
              warehouse: WAREHOUSE__DBT
              target_lag: '1 hour'
          post_hook:
            - "{{ dbt_snow_cortex.apply_cortex_search_config() }}"
  #}
{% if execute %}
{% set node = graph.nodes[this.unique_id] %}
{% set cs = node.config.meta.get('cortex_search') %}
{% if cs is none %}
      {{ exceptions.raise_compiler_error(
        "dbt_snow_cortex.apply_cortex_search_config: no 'cortex_search' found in config.meta on model " ~ this
      ) }}
{% endif %}
    {{ return(dbt_snow_cortex.create_cortex_search_service(
      service_name=cs.get('service_name'),
      search_column=cs.get('search_column'),
      primary_key_columns=cs.get('primary_key_columns', []),
      attribute_columns=cs.get('attribute_columns', []),
      source_query=cs.get('source_query'),
      source_query_casts=cs.get('source_query_casts', {}),
      warehouse=cs.get('warehouse', 'COMPUTE_WH'),
      target_lag=cs.get('target_lag', '1 hour'),
      refresh_mode=cs.get('refresh_mode', 'INCREMENTAL')
    )) }}
{% endif %}
{% endmacro %}
