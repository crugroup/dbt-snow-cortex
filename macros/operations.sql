{% macro list_cortex_search_services(database=none, schema=none) %}
  {{ return(adapter.dispatch('list_cortex_search_services', 'dbt_snow_cortex')(
    database=database,
    schema=schema
  )) }}
{% endmacro %}


{% macro snowflake__list_cortex_search_services(database, schema) %}
  {#
    Lists all Cortex Search Services in a database (optionally filtered by schema).

    Usage:
        dbt run-operation dbt_snow_cortex.list_cortex_search_services \
          --args '{database: ANALYTICS_DB, schema: CORTEX}'
  #}
  {% set _database = database if database is not none else target.database %}

  {% set query %}
    SELECT
      service_catalog AS database_name,
      service_schema AS schema_name,
      service_name,
      search_column,
      target_lag,
      warehouse,
      data_timestamp
    FROM {{ adapter.quote(_database) }}.INFORMATION_SCHEMA.CORTEX_SEARCH_SERVICES
    {% if schema is not none %}
    WHERE service_schema = '{{ schema | upper }}'
    {% endif %}
    ORDER BY
      service_schema,
      service_name
  {% endset %}

  {% if execute %}
    {% set results = run_query(query) %}
    {% set header = "Cortex Search Services in " ~ _database
      ~ (("." ~ schema) if schema is not none else "") ~ ":" %}
    {{ log(header, info=true) }}
    {{ log("=" * 80, info=true) }}
    {% if results | length == 0 %}
      {{ log("No Cortex Search Services found.", info=true) }}
    {% else %}
      {% for row in results %}
        {{ log(
          row[1] ~ "." ~ row[2]
          ~ " | ON " ~ row[3]
          ~ " | lag=" ~ row[4]
          ~ " | wh=" ~ row[5],
          info=true
        ) }}
      {% endfor %}
    {% endif %}
  {% endif %}

{% endmacro %}


{% macro default__list_cortex_search_services() %}
  {{ exceptions.raise_compiler_error("dbt_snow_cortex only supports Snowflake") }}
{% endmacro %}


{# ---------------------------------------------------------------------------
   Helper macros that return agate result sets for programmatic use.
   These are used by verify_cortex_deployment and similar macros.
   For interactive listing, use list_cortex_search_services.
--------------------------------------------------------------------------- #}


{% macro get_cortex_search_services(database=none, schema=none) %}
  {#
    Returns an agate result set of Cortex Search Services.
    Filters by schema when provided.
    Useful for programmatic existence checks.
  #}
  {{ return(adapter.dispatch('get_cortex_search_services', 'dbt_snow_cortex')(
    database=database, schema=schema
  )) }}
{% endmacro %}

{% macro snowflake__get_cortex_search_services(database, schema) %}
  {% set _database = database if database is not none else target.database %}
  {% set query %}
    SELECT
      service_schema AS schema_name,
      service_name
    FROM {{ adapter.quote(_database) }}.INFORMATION_SCHEMA.CORTEX_SEARCH_SERVICES
    {% if schema is not none %}
    WHERE service_schema = '{{ schema | upper }}'
    {% endif %}
    ORDER BY service_schema, service_name
  {% endset %}
  {% if execute %}
    {{ return(run_query(query)) }}
  {% else %}
    {{ return(none) }}
  {% endif %}
{% endmacro %}

{% macro default__get_cortex_search_services() %}
  {{ exceptions.raise_compiler_error("dbt_snow_cortex only supports Snowflake") }}
{% endmacro %}


{% macro collect_cortex_deployment_status(
  database=none,
  schema=none,
  expected_search_services=none
) %}
  {{ return(adapter.dispatch('collect_cortex_deployment_status', 'dbt_snow_cortex')(
    database=database,
    schema=schema,
    expected_search_services=expected_search_services
  )) }}
{% endmacro %}


{% macro snowflake__collect_cortex_deployment_status(
  database,
  schema,
  expected_search_services
) %}
  {% set _database = database if database is not none else target.database %}
  {% set _schema = schema if schema is not none else none %}
  {% set _expected_search_services = expected_search_services if expected_search_services is not none else [] %}

  {% set existing_search_services = [] %}

  {% if execute %}
    {% set css_result = dbt_snow_cortex.get_cortex_search_services(database=_database, schema=_schema) %}
    {% if css_result is not none %}
      {% for row in css_result %}
        {% do existing_search_services.append(row[1] | upper) %}
      {% endfor %}
    {% endif %}
  {% endif %}

  {% set found_search_services = [] %}
  {% set missing_search_services = [] %}
  {% for service_name in _expected_search_services %}
    {% if service_name | upper in existing_search_services %}
      {% do found_search_services.append(service_name) %}
    {% else %}
      {% do missing_search_services.append(service_name) %}
    {% endif %}
  {% endfor %}

  {% set status = {
    'database': _database,
    'schema': _schema,
    'expected_search_services': _expected_search_services,
    'found_search_services': found_search_services,
    'missing_search_services': missing_search_services
  } %}

  {{ return(status) }}
{% endmacro %}


{% macro default__collect_cortex_deployment_status() %}
  {{ exceptions.raise_compiler_error("dbt_snow_cortex only supports Snowflake") }}
{% endmacro %}


{% macro log_cortex_deployment_summary(
  database=none,
  schema=none,
  expected_search_services=none
) %}
  {{ return(adapter.dispatch('log_cortex_deployment_summary', 'dbt_snow_cortex')(
    database=database,
    schema=schema,
    expected_search_services=expected_search_services
  )) }}
{% endmacro %}


{% macro snowflake__log_cortex_deployment_summary(
  database,
  schema,
  expected_search_services
) %}
  {% set status = dbt_snow_cortex.collect_cortex_deployment_status(
    database=database,
    schema=schema,
    expected_search_services=expected_search_services
  ) %}

  {% if execute %}
    {% set schema_label = status['schema'] if status['schema'] is not none else '*' %}
    {{ log('Cortex deployment summary for ' ~ status['database'] ~ '.' ~ schema_label, info=true) }}
    {{ log('=' * 80, info=true) }}

    {% for service_name in status['expected_search_services'] %}
      {% if service_name in status['found_search_services'] %}
        {{ log('SEARCH SERVICE FOUND: ' ~ service_name, info=true) }}
      {% else %}
        {{ log('SEARCH SERVICE MISSING: ' ~ service_name, info=true) }}
      {% endif %}
    {% endfor %}

    {{ log(
      'Summary totals: '
      ~ 'search_services_found=' ~ (status['found_search_services'] | length)
      ~ ', search_services_missing=' ~ (status['missing_search_services'] | length),
      info=true
    ) }}
  {% endif %}

  {{ return(status) }}
{% endmacro %}


{% macro default__log_cortex_deployment_summary() %}
  {{ exceptions.raise_compiler_error("dbt_snow_cortex only supports Snowflake") }}
{% endmacro %}


{% macro assert_cortex_deployment(
  database=none,
  schema=none,
  expected_search_services=none,
  fail_if_missing=true
) %}
  {{ return(adapter.dispatch('assert_cortex_deployment', 'dbt_snow_cortex')(
    database=database,
    schema=schema,
    expected_search_services=expected_search_services,
    fail_if_missing=fail_if_missing
  )) }}
{% endmacro %}


{% macro snowflake__assert_cortex_deployment(
  database,
  schema,
  expected_search_services,
  fail_if_missing
) %}
  {% set status = dbt_snow_cortex.log_cortex_deployment_summary(
    database=database,
    schema=schema,
    expected_search_services=expected_search_services
  ) %}

  {% set missing_objects = [] %}
  {% for service_name in status['missing_search_services'] %}
    {% do missing_objects.append('SEARCH SERVICE: ' ~ service_name) %}
  {% endfor %}

  {% if execute and (missing_objects | length > 0) %}
    {% set msg = 'Cortex deployment assertion failed. Missing objects: ' ~ (missing_objects | join(', ')) %}
    {% if fail_if_missing %}
      {{ exceptions.raise_compiler_error(msg) }}
    {% else %}
      {{ log(msg, info=true) }}
    {% endif %}
  {% endif %}

  {{ return(status) }}
{% endmacro %}


{% macro default__assert_cortex_deployment() %}
  {{ exceptions.raise_compiler_error("dbt_snow_cortex only supports Snowflake") }}
{% endmacro %}
