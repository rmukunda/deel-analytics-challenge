# Deel Analytics Engineering Challenge — Globepay Card Payments

## 1. Business context

Deel clients fund their Deel account with credit/debit cards. Card processing is
outsourced to **Globepay**, a global payment processor that can process many
currencies from cards issued in many countries. Deel calls the Globepay API with
the client's card details and transaction data; Globepay returns the outcome of
each attempt (accepted/declined) and, separately, reports any chargebacks raised
against past transactions.

A Data Analyst asked for a model that can answer, at minimum:

1. What is the acceptance rate over time?
2. Which countries had more than $25M in declined transactions?
3. Which transactions are missing chargeback data?

No schema was supplied with the three source files — the shapes and semantics
below were reverse-engineered from the raw data (see §3).

## 2. Repo structure

```
deel_dbt/
├── seeds/                          raw source files, loaded as-is
│   ├── acceptance_transactions.csv     Globepay payment attempts
│   ├── chargeback_report.csv           Globepay chargeback outcomes
│   └── countries.csv                   country/currency reference data (hand-built)
├── models/
│   ├── staging/                    1:1 with sources, renamed/typed, no business logic
│   ├── intermediate/               joins + FX conversion logic
│   └── marts/                      analyst-facing star schema
├── macros/
│   ├── get_fx_rate_to_usd.sql       pulls a currency's rate out of the raw JSON rate map
│   └── get_custom_schema.sql        flattens custom schema naming (dbt convention override)
└── packages.yml                    dbt_utils (date_spine, expression tests)
```

## 3. Preliminary data exploration

| File | Rows | Grain | Key fields |
|---|---|---|---|
| `acceptance_transactions.csv` | 5,430 | 1 row per payment attempt | `external_ref` (PK), `state` (ACCEPTED/DECLINED), `amount`, `currency`, `country`, `rates` (JSON map of FX→USD), `cvv_provided`, `date_time` |
| `chargeback_report.csv` | 5,430 | 1 row per transaction | `external_ref` (PK), `chargeback` (boolean) |
| `countries.csv` | 6 | 1 row per country | `country_id`, `country_code`, `country_name`, `currency_code` |

Findings from profiling the raw data:

- **`external_ref` is the shared key** between the two Globepay files (confirmed
  by name against the Globepay API spec) and is unique in both — safe to treat
  as each table's primary key.
- **Every transaction currently has a matching chargeback record** (5,430/5,430
  IDs match in both directions, zero orphans either way). The model still needs
  to support "missing chargeback data" as a first-class case, since the two
  feeds arrive independently and won't stay in lockstep in production (the
  chargeback feed lags — a chargeback can only be reported after the fact).
- **`status` is a boolean present on both feeds and always `TRUE`** in the
  current data — it does not appear in Globepay's documented API response
  shape and its meaning is unconfirmed. Carried through as-is rather than
  dropped, but not used in any business logic.
- **`rates` is a JSON map of currency → rate-to-USD**, snapshotted per
  transaction at the time it occurred (rates drift across the file). Globepay
  settles in USD, so this is the correct rate to use for USD conversions.
  Because the map is USD-denominated (`rate = units of currency per 1 USD`),
  converting an amount to USD is `amount / rate`, i.e. `amount * (1 / rate)`.
- **Card country codes** in the data: `AE, CA, FR, MX, UK, US`. Note `UK` is
  used instead of the ISO-3166 `GB` — this is consistent across the source
  files and the hand-built `countries.csv`, so it's treated as the source
  system's convention rather than fixed/remapped.
- **Date range**: 2019-01-01 through 2019-06-30 (six months, half-hourly-ish
  cadence). `dim_calendar` is spined well beyond this range (2018–2027) so the
  mart isn't limited to the current data load.
- **One negative `amount`** was found (a likely refund/adjustment or data
  anomaly) — flagged rather than filtered (see `transaction_anomoly` below),
  since Analytics shouldn't silently drop revenue-shaped rows without the
  business confirming they're erroneous.
- `transaction_status` values are exactly `{ACCEPTED, DECLINED}` — no other
  states observed, tested with a `warn`-severity `accepted_values` test in
  case Globepay introduces new states (e.g. `PENDING`) later.

## 4. Model architecture

Standard dbt layering — staging → intermediate → marts — one raw file in, one
fact out:

```
seeds                    staging                intermediate                    marts
──────────────────────────────────────────────────────────────────────────────────────────────
acceptance_transactions ─▶ stg_acceptance ──┐
                                             ├─▶ int_acceptance_chargeback ─▶ fct_acceptance_transactions
chargeback_report ───────▶ stg_chargeback ──┘                                        │
                                                                                       │
countries ───────────────▶ stg_country ──▶ dim_country ────────────────────────────────┤
                                                                                       │
                            dim_calendar (date spine, no source) ─────────────────────┘
```

- **`stg_acceptance` / `stg_chargeback` / `stg_country`** — 1:1 renames/casts
  of the raw seeds to clear, snake_case, documented names (`external_ref` →
  `transaction_id`, `state` → `transaction_status`, etc.). No joins, no
  derived columns. This is the layer that isolates the rest of the project
  from source naming/shape changes — `stg_country` is a straight pass-through
  since `countries` is already clean, but it exists so every mart is built on
  a staging model rather than reaching past it to a bare seed.
- **`int_acceptance_chargeback`** — left-joins chargeback onto acceptance
  (acceptance is the grain we care about; a transaction can exist without a
  chargeback outcome yet, but a chargeback shouldn't exist without a
  transaction). Resolves the per-currency FX rate out of the JSON map via the
  `get_fx_rate_to_usd` macro, in both directions, and flags negative amounts
  as `transaction_anomoly`.
- **`dim_country`** — thin pass-through of `stg_country`.
- **`dim_calendar`** — `dbt_utils.date_spine`-generated day grain with common
  rollup attributes (month, quarter, ISO week, year-month/quarter/week keys)
  so time-series questions don't need date arithmetic repeated in every query.
- **`fct_acceptance_transactions`** — the analyst-facing mart. One row per
  transaction; card country/currency codes are resolved to `dim_country.country_id`
  rather than kept as raw codes, and `transaction_date_key` is exposed as an
  explicit FK into `dim_calendar`. Materialized as a table (staging/intermediate
  are views) since this is the model the BI layer/analysts query directly.

Run `dbt docs generate && dbt docs serve` for the interactive lineage graph —
this is more informative than a static diagram here since dbt keeps it in sync
with the actual `ref()`/`source()` graph.

## 5. Macros, validation, documentation — notes for future contributors

- **Macros**: `get_fx_rate_to_usd(fx_rates_to_usd, currency)` centralizes the
  "pull one currency out of a JSON rate map and cast it" logic so it isn't
  copy-pasted anywhere a rate is needed. Keep FX/currency logic like this in a
  macro rather than inline SQL — it's the kind of one-liner that's easy to get
  subtly wrong (direction of the rate, cast precision) in a second copy.
- **Data validation**: tests are split by confidence —
  - `unique` / `not_null` on every primary and foreign key (`transaction_id`,
    `country_id`, `transaction_date_key`) at `error` severity, since a
    violation there silently breaks joins downstream.
  - `accepted_values` on `transaction_status` and a non-negative check on
    `transaction_amount` are set to `warn`, because both are things Globepay
    could legitimately introduce (new states, refunds/adjustments) without it
    being a pipeline bug — `warn` surfaces it without breaking the run.
  - Add a `dbt_utils.relationships`-style check (or a singular test) asserting
    row counts don't shrink across `stg_acceptance → int_acceptance_chargeback`
    as a regression guard, since that join is a `left join` specifically to
    preserve every acceptance row.
- **Documentation**: every model and column has a `description:` in its
  `models.yaml`, including *why* a field's meaning is uncertain (e.g. `status`)
  rather than guessing — a wrong guess baked into docs is worse than an
  honest "unconfirmed." Keep new columns documented in the same PR that adds
  them; `dbt docs generate` will flag gaps if you enable `--strict`/CI doc
  coverage checks later.

## 6. Part 2 — answering the analyst's questions

All three questions run directly against `fct_acceptance_transactions`
(joined to `dim_calendar` / `dim_country` as needed) — that's the point of the
mart layer, so the analyst never has to re-derive FX conversion or re-join
chargebacks themselves.

### Q1 — Acceptance rate over time

```sql
select
    c.year_month,
    count_if(f.transaction_status = 'ACCEPTED')        as accepted_transactions,
    count(*)                                            as total_transactions,
    accepted_transactions / total_transactions           as acceptance_rate
from {{ ref('fct_acceptance_transactions') }} f
join {{ ref('dim_calendar') }} c
    on f.transaction_date_key = c.date_day
group by 1
order by 1
```

Swap `c.year_month` for `c.date_day`, `c.year_week_number`, or `c.year_quarter`
depending on the granularity the analyst wants — that's exactly why the FX/date
logic was pushed into `dim_calendar` instead of computed ad hoc.

**Result on current data** (Jan–Jun 2019, monthly): acceptance rate is stable
around **69–72%** every month (overall 69.6%, 3,777/5,430), no material trend:

| Month | Accepted / Total | Rate |
|---|---|---|
| 2019-01 | 647 / 930 | 69.6% |
| 2019-02 | 589 / 840 | 70.1% |
| 2019-03 | 641 / 930 | 68.9% |
| 2019-04 | 610 / 900 | 67.8% |
| 2019-05 | 645 / 930 | 69.4% |
| 2019-06 | 645 / 900 | 71.7% |

### Q2 — Countries where declined transactions exceeded $25M

```sql
select
    co.country_name,
    sum(f.transaction_amount_usd)  as declined_amount_usd
from {{ ref('fct_acceptance_transactions') }} f
join {{ ref('dim_country') }} co
    on f.country_id = co.country_id
where f.transaction_status = 'DECLINED'
group by 1
having sum(f.transaction_amount_usd) > 25000000
order by declined_amount_usd desc
```

**Result on current data**: 4 of the 6 countries clear the $25M threshold —

| Country | Declined amount (USD) |
|---|---|
| France | $32.6M |
| United Kingdom | $27.5M |
| United Arab Emirates | $26.3M |
| United States | $25.1M |
| ~~Canada~~ | $18.4M (below threshold) |
| ~~Mexico~~ | $0.9M (below threshold) |

### Q3 — Transactions missing chargeback data

```sql
select *
from {{ ref('fct_acceptance_transactions') }}
where is_chargeback is null
```

`is_chargeback` is `null` only when `int_acceptance_chargeback`'s left join to
`stg_chargeback` found no matching `transaction_id` — i.e. Globepay hasn't (yet)
reported a chargeback outcome for that transaction. **On the current seed data
this returns zero rows** (every transaction has a chargeback record), but the
query — and the left join it depends on — is what protects the analyst when
the two feeds fall out of sync in production, e.g. if the chargeback feed is
ingested on a lag relative to the acceptance feed.

## 7. Running the project

```bash
dbt deps      # install dbt_utils
dbt seed      # load the three raw CSVs
dbt run       # build staging → intermediate → marts
dbt test      # run schema + data tests
dbt docs generate && dbt docs serve   # browse lineage graph + docs
```
