# Jaffle Shop — Data Lineage & Flow

> How data flows through this dbt project, from raw CSV seeds to the final
> analytics marts. This describes a **cold start**: nothing exists in Snowflake yet.
>
> Target warehouse (from `profiles.yml` → `jaffle_shop_dbt_project`):
> **database** `DBTPROJECTDB`, **dev schema** `dev`, **seed schema** `raw`.

---

## 1. Lineage graph (the DAG)

```mermaid
flowchart LR
    %% ---------- SEEDS ----------
    subgraph SEEDS["🌱 Seeds — CSV files (seeds/jaffle-data)"]
        direction TB
        c_cust[raw_customers.csv]
        c_ord[raw_orders.csv]
        c_item[raw_items.csv]
        c_store[raw_stores.csv]
        c_prod[raw_products.csv]
        c_sup[raw_supplies.csv]
    end

    %% ---------- SOURCES ----------
    subgraph RAW["🗄️ Snowflake schema: raw (sources — 'ecom')"]
        direction TB
        s_cust[(raw_customers)]
        s_ord[(raw_orders)]
        s_item[(raw_items)]
        s_store[(raw_stores)]
        s_prod[(raw_products)]
        s_sup[(raw_supplies)]
    end

    %% ---------- STAGING ----------
    subgraph STG["🔎 Staging — views in schema: dev"]
        direction TB
        stg_customers{{stg_customers}}
        stg_orders{{stg_orders}}
        stg_order_items{{stg_order_items}}
        stg_locations{{stg_locations}}
        stg_products{{stg_products}}
        stg_supplies{{stg_supplies}}
    end

    %% ---------- MARTS ----------
    subgraph MARTS["🏛️ Marts — tables in schema: dev"]
        direction TB
        fct_order_items[fct_order_items]
        fct_orders["fct_orders<br/><i>(incremental)</i>"]
        dim_customers[dim_customers]
        dim_locations[dim_locations]
        dim_products[dim_products]
        dim_supplies[dim_supplies]
    end

    %% seed -> raw
    c_cust --> s_cust
    c_ord --> s_ord
    c_item --> s_item
    c_store --> s_store
    c_prod --> s_prod
    c_sup --> s_sup

    %% raw -> staging
    s_cust --> stg_customers
    s_ord --> stg_orders
    s_item --> stg_order_items
    s_store --> stg_locations
    s_prod --> stg_products
    s_sup --> stg_supplies

    %% staging -> marts
    stg_order_items --> fct_order_items
    stg_orders --> fct_order_items
    stg_products --> fct_order_items
    stg_supplies --> fct_order_items
    stg_orders --> fct_orders
    stg_customers --> dim_customers
    stg_locations --> dim_locations
    stg_products --> dim_products
    stg_supplies --> dim_supplies

    %% marts -> marts
    fct_order_items --> fct_orders
    fct_orders --> dim_customers

    classDef seed fill:#fef9c3,stroke:#ca8a04,color:#713f12;
    classDef src fill:#e0f2fe,stroke:#0284c7,color:#075985;
    classDef stg fill:#ede9fe,stroke:#7c3aed,color:#4c1d95;
    classDef mart fill:#dcfce7,stroke:#16a34a,color:#14532d;

    class c_cust,c_ord,c_item,c_store,c_prod,c_sup seed;
    class s_cust,s_ord,s_item,s_store,s_prod,s_sup src;
    class stg_customers,stg_orders,stg_order_items,stg_locations,stg_products,stg_supplies stg;
    class fct_order_items,fct_orders,dim_customers,dim_locations,dim_products,dim_supplies mart;
```

---

## 2. The layers explained

| Layer | What it is | Materialization | Snowflake location |
|-------|-----------|-----------------|--------------------|
| **Seeds** | 6 CSV files shipped in the repo (`seeds/jaffle-data/`). Gated behind `var('load_source_data')`. | `seed` → tables | `DBTPROJECTDB.raw.*` |
| **Sources** | Logical pointers (`ecom`) to the raw tables the seeds create. Defined in `models/staging/__sources.yml`. | — (not built) | `DBTPROJECTDB.raw.*` |
| **Staging** | 1:1 cleanup/renaming of each source. Light transforms only. | `view` | `DBTPROJECTDB.dev.stg_*` |
| **Marts** | Business-level fact (`fct_`) and dimension (`dim_`) tables, analytics-ready. | `table` (except `fct_orders` = `incremental`) | `DBTPROJECTDB.dev.*` |

### Dependency edges (exact, from the SQL)

- `stg_customers`  ← source `ecom.raw_customers`
- `stg_orders`     ← source `ecom.raw_orders`
- `stg_order_items`← source `ecom.raw_items`
- `stg_locations`  ← source `ecom.raw_stores`
- `stg_products`   ← source `ecom.raw_products`
- `stg_supplies`   ← source `ecom.raw_supplies`
- `fct_order_items`← `stg_order_items`, `stg_orders`, `stg_products`, `stg_supplies`
- `fct_orders`     ← `stg_orders`, `fct_order_items`
- `dim_customers`  ← `stg_customers`, `fct_orders`
- `dim_locations`  ← `stg_locations`
- `dim_products`   ← `stg_products`
- `dim_supplies`   ← `stg_supplies`

> **Build order dbt computes from this DAG:** seeds → all 6 staging views →
> `fct_order_items` → `fct_orders` → `dim_customers` (+ `dim_locations`,
> `dim_products`, `dim_supplies` run as soon as their inputs exist).

### About the one incremental model

`fct_orders` is materialized **incremental** (`unique_key='order_id'`, `merge` strategy).
- **First run** (table doesn't exist yet): dbt builds it from scratch — the full history.
- **Later runs**: `is_incremental()` is true, so dbt only processes orders newer than the
  max `ordered_at` already loaded, then `merge`s them in on `order_id`.
- Force a rebuild any time with `dbt build --select fct_orders --full-refresh`.

---

## 3. Step-by-step: a cold start (nothing in Snowflake yet)

Assumes real Snowflake credentials are in place for the `jaffle_shop_dbt_project`
profile.

1. **Install package dependencies**
   ```bash
   dbt deps
   ```
   Fetches `dbt_utils` into `dbt_packages/`. *(Already done in this workspace.)*

2. **Sanity-check the connection** (creates nothing)
   ```bash
   dbt debug          # verifies Snowflake login + DBTPROJECTDB access
   dbt parse          # validates the project graph
   ```

3. **Load the raw data from the CSV seeds** — this populates an empty warehouse:
   ```bash
   dbt seed --full-refresh --vars '{"load_source_data": true}'
   ```
   - Creates schema `DBTPROJECTDB.raw` and loads the 6 CSVs into `raw.raw_*`.
   - Without `load_source_data: true` the seeds stay **disabled** and the sources
     would have nothing to read.

4. **Build the models and run all tests**
   ```bash
   dbt build
   ```
   Runs each node in DAG order and tests it before dependents run: 6 `stg_*` views,
   then `fct_order_items` → `fct_orders` → `dim_customers`, plus the three other
   dimensions — alongside the generic tests, the singular test, and the unit test.

5. **(Optional) Explore**
   ```bash
   dbt docs generate && dbt docs serve   # browsable lineage + catalog
   dbt show --select fct_orders          # preview rows
   ```

### What exists in Snowflake after step 4

```
DBTPROJECTDB
├── raw   (from dbt seed)
│   ├── raw_customers        (table)
│   ├── raw_orders           (table)
│   ├── raw_items            (table)
│   ├── raw_stores           (table)
│   ├── raw_products         (table)
│   └── raw_supplies         (table)
└── dev   (from dbt build)
    ├── stg_customers        (view)
    ├── stg_orders           (view)
    ├── stg_order_items      (view)
    ├── stg_locations        (view)
    ├── stg_products         (view)
    ├── stg_supplies         (view)
    ├── fct_order_items      (table)
    ├── fct_orders           (table, incremental)
    ├── dim_customers        (table)
    ├── dim_locations        (table)
    ├── dim_products         (table)
    └── dim_supplies         (table)
```

> Schema routing comes from `macros/generate_schema_name.sql`: seeds are forced
> into a literal `raw` schema, while every other model lands in the target schema
> (`dev`). With the `prod` target, custom schemas would be prefixed (e.g. `prod_…`).
