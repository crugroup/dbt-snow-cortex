{% macro create_or_replace_semantic_view(
  view_name,
  yaml_content=none,
  yaml_file_path=none,
  database=none,
  schema='CORTEX_ANALYST',
  replace=true,
  create_mode='on_change'
) %}
  {{ return(adapter.dispatch('create_or_replace_semantic_view', 'dbt_snow_cortex')(
    view_name=view_name,
    yaml_content=yaml_content,
    yaml_file_path=yaml_file_path,
    database=database,
    schema=schema,
    replace=replace,
    create_mode=create_mode
  )) }}
{% endmacro %}


{% macro snowflake__create_or_replace_semantic_view(
  view_name,
  yaml_content,
  yaml_file_path,
  database,
  schema,
  replace,
  create_mode
) %}
  {#
    Creates (or replaces) a Snowflake native Semantic View from a YAML specification
    using the SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML stored procedure.

    The YAML format follows the Cortex Analyst semantic model specification:
    https://docs.snowflake.com/user-guide/views-semantic/semantic-view-yaml-spec

    Args:
        view_name:           Name of the semantic view to create.
        yaml_content:        YAML string. Required when yaml_file_path is not provided.
        yaml_file_path:      (unused — pass yaml_content directly in on-run-end hooks;
                             use dbt run-operation and pass yaml_content inline).
        database:            Target database. Defaults to the current target database.
        schema:              Target schema (default: CORTEX_ANALYST).
        replace:             If false and the view already exists, skip creation (default: true).
        create_mode:         'on_change' (default): skip when the existing view was created from
                             the same YAML, identified by an MD5 marker appended to its COMMENT.
                             'replace': recreate the view on every run.

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

  {% if create_mode not in ['replace', 'on_change'] %}
    {{ exceptions.raise_compiler_error(
      "dbt_snow_cortex.create_or_replace_semantic_view: 'create_mode' must be 'replace' or 'on_change', got '"
      ~ create_mode ~ "'."
    ) }}
  {% endif %}

  {% set _database = database if database is not none else target.database %}
  {% set _q_db = adapter.quote(_database) %}
  {% set _q_sch = adapter.quote(schema) %}
  {% set _q_vn = adapter.quote(view_name) %}
  {% set _target_schema = _q_db ~ '.' ~ _q_sch %}

  {#
    The hash covers the fully-qualified name and the YAML as written. Whitespace is not
    collapsed because YAML indentation is structural.
  #}
  {% set _fingerprint = (_database ~ '.' ~ schema ~ '.' ~ view_name) | upper
    ~ ' ' ~ (yaml_content | trim) %}
  {% set _marker = '[dbt_snow_cortex:def_md5=' ~ local_md5(_fingerprint) ~ ']' %}

  {% if execute %}
    {# Check whether the view already exists to honour replace=false #}
    {% if not replace %}
      {% set exists_query %}
        SELECT COUNT(*) AS cnt
        FROM {{ _q_db }}.INFORMATION_SCHEMA.SEMANTIC_VIEWS
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

    {% if create_mode == 'on_change' %}
      {% set existing_comment = dbt_snow_cortex.get_semantic_view_comment(_target_schema, view_name) %}
      {% if existing_comment is not none and existing_comment.endswith(_marker) %}
        {{ log(
          'dbt_snow_cortex: semantic view ' ~ _q_vn ~ ' in ' ~ _target_schema
          ~ ' unchanged — skipping.',
          info=true
        ) }}
        {% do return('') %}
      {% endif %}
    {% endif %}

    {{ log(
      'dbt_snow_cortex: creating semantic view ' ~ _q_vn
      ~ ' in ' ~ _target_schema,
      info=true
    ) }}

    {# Dollar-quote the YAML. Replace any $$ inside the content to avoid breaking #}
    {% set safe_yaml = yaml_content | replace('$$', '$ $') %}

    {% set create_sql %}
      CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
        '{{ _q_db }}.{{ _q_sch }}',
        $$
{{ safe_yaml }}
        $$
      )
    {% endset %}

    {% do run_query(create_sql) %}

    {#
      Append the marker to the comment set from the YAML description, so on_change runs
      can detect an unchanged definition. Stamped in both modes.
    #}
    {% set description = dbt_snow_cortex.get_semantic_view_comment(_target_schema, view_name) or '' %}
    {% set description = description.split('[dbt_snow_cortex:def_md5=')[0] | trim %}
    {% set new_comment = ((description ~ ' ') if description else '') ~ _marker %}
    {% set comment_sql %}
      ALTER SEMANTIC VIEW {{ _target_schema }}.{{ view_name }}
        SET COMMENT = '{{ new_comment | replace("\\", "\\\\") | replace("'", "''") }}'
    {% endset %}
    {% do run_query(comment_sql) %}

    {{ log(
      'dbt_snow_cortex: semantic view ' ~ _q_vn ~ ' created successfully in '
      ~ _target_schema ~ '.',
      info=true
    ) }}

  {% endif %}

{% endmacro %}


{% macro get_semantic_view_comment(target_schema, view_name) %}
  {# Returns the COMMENT of the semantic view, or none when it does not exist. #}
  {% set show_sql %}
    SHOW SEMANTIC VIEWS LIKE '{{ view_name }}' IN SCHEMA {{ target_schema }}
  {% endset %}
  {% for row in run_query(show_sql) %}
    {% if row['name'] | upper == view_name | upper %}
      {{ return(row['comment'] or '') }}
    {% endif %}
  {% endfor %}
  {{ return(none) }}
{% endmacro %}


{% macro default__create_or_replace_semantic_view() %}
  {{ exceptions.raise_compiler_error("dbt_snow_cortex only supports Snowflake") }}
{% endmacro %}
