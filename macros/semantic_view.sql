{% macro create_or_replace_semantic_view(
  view_name,
  yaml_content=none,
  yaml_file_path=none,
  database=none,
  schema='CORTEX_ANALYST',
  replace=true
) %}
  {{ return(adapter.dispatch('create_or_replace_semantic_view', 'dbt_snow_cortex')(
    view_name=view_name,
    yaml_content=yaml_content,
    yaml_file_path=yaml_file_path,
    database=database,
    schema=schema,
    replace=replace
  )) }}
{% endmacro %}


{% macro snowflake__create_or_replace_semantic_view(
  view_name,
  yaml_content,
  yaml_file_path,
  database,
  schema,
  replace
) %}
  {#
    Creates (or replaces) a Snowflake native Semantic View from a YAML specification
    using the SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML stored procedure.

    The YAML format follows the Cortex Analyst semantic model specification:
    https://docs.snowflake.com/user-guide/views-semantic/semantic-view-yaml-spec

    Args:
        view_name:     Name of the semantic view to create.
        yaml_content:  YAML string. Required when yaml_file_path is not provided.
        yaml_file_path: (unused — pass yaml_content directly in on-run-end hooks;
                        use dbt run-operation and pass yaml_content inline).
        database:      Target database. Defaults to the current target database.
        schema:        Target schema (default: CORTEX_ANALYST).
        replace:       If false and the view already exists, skip creation (default: true).

    Usage (dbt run-operation):
        dbt run-operation dbt_snow_cortex.create_or_replace_semantic_view \
          --args '{view_name: PRODUCT_ANALYST, database: ANALYTICS_DB, schema: CORTEX,
                   yaml_content: "<paste yaml here>"}'

    Usage (from a wrapper macro):
        {{ dbt_snow_cortex.create_or_replace_semantic_view(
               view_name='PRODUCT_ANALYST',
               yaml_content=my_yaml_string,
               database='ANALYTICS_DB',
               schema='CORTEX') }}
  #}

  {% if yaml_content is none %}
    {{ exceptions.raise_compiler_error(
      "dbt_snow_cortex.create_or_replace_semantic_view: 'yaml_content' is required. "
      ~ "Pass the YAML specification as a string via the yaml_content argument."
    ) }}
  {% endif %}

  {% set _database = database if database is not none else target.database %}
  {% set _target_schema = _database ~ '.' ~ schema %}

  {% if execute %}
    {# Check whether the view already exists to honour replace=false #}
    {% if not replace %}
      {% set exists_query %}
        SELECT COUNT(*) AS cnt
        FROM {{ _database }}.INFORMATION_SCHEMA.SEMANTIC_VIEWS
        WHERE CATALOG = '{{ _database | upper }}'
          AND SCHEMA  = '{{ schema | upper }}'
          AND NAME    = '{{ view_name | upper }}'
      {% endset %}
      {% set exists_result = run_query(exists_query) %}
      {% set already_exists = (exists_result.rows[0][0] | int) > 0 %}
      {% if already_exists %}
        {{ log(
          'dbt_snow_cortex: semantic view ' ~ view_name ~ ' already exists — skipping. '
          ~ 'Pass replace=true to overwrite.',
          info=true
        ) }}
        {% do return('') %}
      {% endif %}
    {% endif %}

    {{ log(
      'dbt_snow_cortex: creating semantic view ' ~ view_name
      ~ ' in ' ~ _target_schema,
      info=true
    ) }}

    {# Dollar-quote the YAML. Replace any $$ inside the content to avoid breaking #}
    {% set safe_yaml = yaml_content | replace('$$', '$ $') %}

    {% set create_sql %}
      CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
        '{{ _target_schema }}',
        $$
{{ safe_yaml }}
        $$
      )
    {% endset %}

    {% do run_query(create_sql) %}
    {{ log(
      'dbt_snow_cortex: semantic view ' ~ view_name ~ ' created successfully in '
      ~ _target_schema ~ '.',
      info=true
    ) }}
  {% endif %}

{% endmacro %}


{% macro default__create_or_replace_semantic_view() %}
  {{ exceptions.raise_compiler_error("dbt_snow_cortex only supports Snowflake") }}
{% endmacro %}
