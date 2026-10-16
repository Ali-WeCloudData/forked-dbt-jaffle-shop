{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set default_schema = target.schema -%}

    {# Seeds go into a single, shared `raw` schema (no target prefix), so the #}
    {# sources in _sources.yml can always find them at `<database>.raw.*`.      #}
    {%- if node.resource_type == 'seed' -%}
        {{ custom_schema_name | trim }}

    {# Models with no +schema stay in the target schema (e.g. `dev`).          #}
    {%- elif custom_schema_name is none -%}
        {{ default_schema }}

    {# Models with a +schema are prefixed with the target schema, dbt's        #}
    {# default behaviour: dev + stg -> dev_stg, prod + marts -> prod_marts.    #}
    {# This keeps every developer's build isolated and dev separate from prod. #}
    {%- else -%}
        {{ default_schema }}_{{ custom_schema_name | trim }}

    {%- endif -%}

{%- endmacro %}
