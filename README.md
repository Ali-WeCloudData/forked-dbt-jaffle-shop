# 🥪 Jaffle Shop — dbt Demo Project

A compact, fully-runnable [dbt](https://www.getdbt.com/) project that models a fictional
restaurant, **Jaffle Shop**. It is built as a **teaching demo for dbt fundamentals** on
Snowflake — small enough to walk through in a single session, while still covering the
core features you use on real projects.

> Runs on the **dbt Fusion engine (v2.x)** against **Snowflake**. Based on dbt Labs'
> [`jaffle-shop`](https://github.com/dbt-labs/jaffle-shop), trimmed and restructured for teaching.

---

## What this project demonstrates

- **Sources & seeds** — raw CSVs loaded as the project's source data
- **Layered modeling** — `staging` → `intermediate` → `marts` (facts & dimensions)
- **Materializations** — `view`, `table`, and an **`incremental`** fact model
- **Custom schemas** — `generate_schema_name` routing (`dev_stg`, `dev_marts`, …)
- **Jinja & macros** — a reusable `cents_to_dollars` macro and `dbt_utils` helpers
- **Packages** — `dbt_utils`
- **Testing** — generic, singular, and **unit** tests
- **Snapshots** — SCD Type 2 history of product prices
- **Documentation** — model/column descriptions, `doc()` blocks, and the dbt docs site

---

## Data model

Data flows **raw (seeds) → staging (views) → intermediate (view) → marts (tables) → BI**,
with a **snapshot** tracking how product attributes change over time.

| Layer | Models | Materialization | Warehouse schema |
|-------|--------|-----------------|------------------|
| **Sources / seeds** | `raw_customers`, `raw_orders`, `raw_items`, `raw_products`, `raw_supplies` | `seed` → table | `raw` |
| **Staging** | `stg_customers`, `stg_orders`, `stg_order_items`, `stg_products`, `stg_supplies` | `view` | `dev_stg` |
| **Intermediate** | `int_supplies_cost_per_product` | `view` | `dev_intermediate` |
| **Marts** | `fct_order_items`, `fct_orders` *(incremental)*, `dim_customers`, `dim_products` | `table` | `dev_marts` |
| **Snapshot** | `products_snapshot` | `snapshot` | `dev_snapshots` |

> Run `dbt docs serve` for the interactive lineage graph and full catalog.

### Why these materializations?

- **`fct_orders` is incremental** — orders are a large, continuously growing fact table, so
  later runs process only new orders instead of rebuilding everything.
- **`products_snapshot` is a snapshot** — products are a small, slowly-changing dimension
  whose *price* changes over time, so SCD Type 2 keeps full price history.

*Rule of thumb: incrementally load growing facts; snapshot slowly-changing dimensions.*

---

## Project structure

```
.
├── dbt_project.yml          # project config, folder-level materializations & schemas
├── packages.yml             # dbt packages (dbt_utils)
├── models/
│   ├── staging/             # 1:1 cleanup of each source (views)
│   │   ├── _sources.yml     # source definitions
│   │   └── _models.yml      # staging model docs & tests
│   ├── intermediate/        # reusable mid-logic (view)
│   └── marts/               # business-facing facts & dimensions (tables)
│   └── docs.md              # shared {% docs %} blocks
├── seeds/jaffle-data/       # raw CSV data (loaded via `dbt seed`)
├── snapshots/               # products_snapshot (SCD2)
├── macros/                  # cents_to_dollars, generate_schema_name
└── tests/                   # singular data tests
```

---

## Prerequisites

- **dbt (Fusion engine, v2.0+)** — this project sets `require-dbt-version: ">=2.0.0"`.
  The Snowflake adapter is bundled with the engine (no separate `dbt-snowflake` install).
- A **Snowflake** account with permission to create schemas in a database.
- *(optional)* **Python 3.9+** to manage a virtual environment.

---

## Setup

**1. Clone the repo**

```bash
git clone https://github.com/Ali-WeCloudData/forked-dbt-jaffle-shop.git
cd forked-dbt-jaffle-shop
```

**2. Install dbt (in a virtual environment)**

```bash
python -m venv .venv
# Windows:  .venv\Scripts\activate
# macOS/Linux:  source .venv/bin/activate
pip install dbt
```

**3. Configure your connection** in `~/.dbt/profiles.yml`

The profile name must match `profile:` in `dbt_project.yml` (`jaffle_shop_dbt_project`).
Keep real credentials out of git — use placeholders or `env_var()`.

```yaml
jaffle_shop_dbt_project:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: "<your_account>"
      user: "<your_user>"
      password: "{{ env_var('SNOWFLAKE_PASSWORD') }}"
      role: "<your_role>"
      warehouse: "<your_warehouse>"
      database: "<your_database>"
      schema: "dev"            # prefix for dev_stg, dev_marts, …
      threads: 4
    prod:
      type: snowflake
      # …same connection…
      schema: "prod"           # prefix for prod_stg, prod_marts, …
      threads: 4
```

**4. Install packages and verify the connection**

```bash
dbt deps
dbt debug
```

---

## Load data & build

The sample data ships as CSV seeds, gated behind a variable so they are not loaded by
accident. On a cold start, load them first:

```bash
# 1. Load the raw CSVs into the `raw` schema
dbt seed --full-refresh --vars '{"load_source_data": true}'

# 2. Build all models, snapshots, and run every test
dbt build
```

After this, you have the full project built in Snowflake and all tests passing.

---

## Common commands

| Command | What it does |
|---------|--------------|
| `dbt build` | Run seeds, models, snapshots, and tests in DAG order (day-to-day command) |
| `dbt run` | Build models only |
| `dbt test` | Run tests only |
| `dbt snapshot` | Capture snapshot changes (SCD2) |
| `dbt docs generate && dbt docs serve` | Build and serve the docs site + lineage graph |
| `dbt build --select staging` | Build only the staging folder |
| `dbt build --select +fct_orders` | `fct_orders` and everything upstream of it |
| `dbt build --select fct_orders+` | `fct_orders` and everything downstream of it |

> **Note on the incremental model:** if you change the columns of `fct_orders`, rebuild it
> once with `dbt build --select fct_orders --full-refresh` so the table picks up the new schema.

---

## Warehouse layout

With the `dev` target, the project builds into:

```
<database>
├── raw               # seeded source tables (shared, not target-prefixed)
├── dev_stg           # staging views
├── dev_intermediate  # intermediate view
├── dev_marts         # fact & dimension tables
└── dev_snapshots     # products_snapshot (SCD2)
```

Seeds always land in a bare `raw` schema; every other model is prefixed with the target
schema (`dev` → `dev_stg`, `prod` → `prod_stg`, …) via `macros/generate_schema_name.sql`.

---

## Testing

All tests run as part of `dbt build` (or on their own with `dbt test`):

- **Generic tests** (`data_tests:` in YAML): `unique`, `not_null`, `relationships`,
  `accepted_values`, and `dbt_utils.expression_is_true`.
- **Singular tests** (`.sql` in `tests/`): e.g. `assert_no_negative_order_totals.sql`.
- **Unit tests** (`unit_tests:` in YAML): test transformation *logic* with mocked inputs —
  one on `fct_orders` (food/drink booleans) and one on `int_supplies_cost_per_product`
  (supply-cost aggregation).

Run a single test by name:

```bash
dbt test --select test_supply_costs_sum_correctly
```

---

## Snapshot (SCD2) demo

`products_snapshot` tracks product **price history**. To see it in action:

```bash
# 1. Edit a price in seeds/jaffle-data/raw_products.csv (e.g. JAF-001: 1100 -> 1300)
dbt seed --select raw_products --full-refresh --vars '{"load_source_data": true}'
dbt snapshot
```

The changed product now has a **closed** historical row (`dbt_valid_to` set) and a new
**current** row (`dbt_valid_to = NULL`):

```sql
select sku, name, price, dbt_valid_from, dbt_valid_to
from <database>.dev_snapshots.products_snapshot
order by sku, dbt_valid_from;
```

---

## Credits

Based on dbt Labs' [`jaffle-shop`](https://github.com/dbt-labs/jaffle-shop) sample project,
adapted and simplified as a hands-on introduction to dbt.
