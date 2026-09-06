{% macro get_fx_rate_to_usd(fx_rates_to_usd, currency) %}

    cast(get(parse_json({{ fx_rates_to_usd }}), {{ currency }}) as decimal(10, 6))

{% endmacro %}
