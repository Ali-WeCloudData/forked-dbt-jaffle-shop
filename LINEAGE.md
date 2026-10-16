# Jaffle Shop — Data Lineage & Flow

> How data flows through this dbt project, from raw CSV seeds to the final
> analytics marts. This describes a **cold start**: nothing exists in Snowflake yet.
>
> Target warehouse (from `profiles.yml` → `jaffle_shop_dbt_project`, `dev` target):
> **database** `JAFFLE_SHOP_DB`. Schemas: `raw` (seeds), `dev_stg` (staging),
> `dev_marts` (marts), `dev_snapshots` (snapshot). The intermediate layer is
> **ephemeral**, so it creates no schema/object.

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
    subgraph RAW["🗄️ schema: raw (sources — 'ecom')"]
        direction TB
        s_cust[(raw_customers)]
        s_ord[(raw_orders)]
        s_item[(raw_items)]
        s_store[(raw_stores)]
        s_prod[(raw_products)]
        s_sup[(raw_supplies)]
    end

    %% ---------- STAGING ----------
    subgraph STG["🔎 Staging — views in schema: dev_stg"]
        direction TB
        stg_customers{{stg_customers}}
        stg_orders{{stg_orders}}
        stg_order_items{{stg_order_items}}
        stg_locations{{stg_locations}}
        stg_products{{stg_products}}
        stg_supplies{{stg_supplies}}
    end

    %% ---------- INTERMEDIATE ----------
    subgraph INT["⚙️ Intermediate — ephemeral (no object)"]
        direction TB
        int_cos["int_customer_orders_summary"]
    end

    %% ---------- MARTS ----------
    subgraph MARTS["🏛️ Marts — tables in schema: dev_marts"]
        direction TB
        fct_order_items[fct_order_items]
        fct_orders["fct_orders<br/><i>(incremental)</i>"]
        dim_customers[dim_customers]
        dim_locations[dim_locations]
        dim_products[dim_products]
        dim_supplies[dim_supplies]
    end

    %% ---------- SNAPSHOT ----------
    subgraph SNAP["📸 Snapshot — schema: dev_snapshots (SCD2)"]
        direction TB
        orders_snapshot["orders_snapshot<br/><i>(check strategy)</i>"]
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

    %% raw -> snapshot (same source as the incremental fct_orders)
    s_ord --> orders_snapshot

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

    %% marts -> intermediate -> marts
    fct_order_items --> fct_orders
    fct_orders --> int_cos
    int_cos --> dim_customers

    classDef seed fill:#fef9c3,stroke:#ca8a04,color:#713f12;
    classDef src fill:#e0f2fe,stroke:#0284c7,color:#075985;
    classDef stg fill:#ede9fe,stroke:#7c3aed,color:#4c1d95;
    classDef int fill:#fae8ff,stroke:#c026d3,color:#701a75;
    classDef mart fill:#dcfce7,stroke:#16a34a,color:#14532d;
    classDef snap fill:#ffedd5,stroke:#ea580c,color:#7c2d12;

    class c_cust,c_ord,c_item,c_store,c_prod,c_sup seed;
    class s_cust,s_ord,s_item,s_store,s_prod,s_sup src;
    class stg_customers,stg_orders,stg_order_items,stg_locations,stg_products,stg_supplies stg;
    class int_cos int;
    class fct_order_items,fct_orders,dim_customers,dim_locations,dim_products,dim_supplies mart;
    class orders_snapshot snap;
```

---

## 2. The layers explained

| Layer | What it is | Materialization | Snowflake location |
|-------|-----------|-----------------|--------------------|
| **Seeds** | 6 CSV files shipped in the repo (`seeds/jaffle-data/`). Gated behind `var('load_source_data')`. | `seed` → tables | `JAFFLE_SHOP_DB.raw.*` |
| **Sources** | Logical pointers (`ecom`) to the raw tables the seeds create. Defined in `models/staging/_sources.yml`. | — (not built) | `JAFFLE_SHOP_DB.raw.*` |
| **Staging** | 1:1 cleanup/renaming of each source. | `view` | `JAFFLE_SHOP_DB.dev_stg.stg_*` |
| **Intermediate** | Re-grains orders to one row per customer before the customers dimension. | `ephemeral` (inlined as a CTE) | **none** — no object created |
| **Marts** | Fact (`fct_`) and dimension (`dim_`) tables, analytics-ready. | `table` (except `fct_orders` = `incremental`) | `JAFFLE_SHOP_DB.dev_marts.*` |
| **Snapshot** | SCD Type 2 history of `raw_orders` (check strategy). | `snapshot` | `JAFFLE_SHOP_DB.dev_snapshots.orders_snapshot` |

### Dependency edges (exact, from the SQL)

- `stg_*` ← their matching `ecom.raw_*` source
- `fct_order_items` ← `stg_order_items`, `stg_orders`, `stg_products`, `stg_supplies`
- `fct_orders` (incremental) ← `stg_orders`, `fct_order_items`
- `int_customer_orders_summary` (ephemeral) ← `fct_orders`
- `dim_customers` ← `stg_customers`, `int_customer_orders_summary`
- `dim_locations` ← `stg_locations` · `dim_products` ← `stg_products` · `dim_supplies` ← `stg_supplies`
- `orders_snapshot` ← source `ecom.raw_orders`

### Incremental vs snapshot — the side-by-side
Both are built from the **same orders source**, so they contrast cleanly:
- **`fct_orders`** (incremental, `merge` on `order_id`) keeps only the **current** state of each order.
- **`orders_snapshot`** (SCD2, `check` strategy on `id`) keeps the **full history**: when a tracked column changes, the old row is closed with `dbt_valid_to` and a new current row is added.

---

## 3. Step-by-step: a cold start

1. `dbt deps` — install `dbt_utils`. *(Already done.)*
2. `dbt debug` / `dbt parse` — verify connection and validate the graph (create nothing).
3. `dbt seed --full-refresh --vars '{"load_source_data": true}'` — load the 6 CSVs into `raw.*`.
4. `dbt build --vars '{"load_source_data": true}'` — builds seeds, staging views, marts, the snapshot, and runs every test (generic, singular, unit) in DAG order. The ephemeral intermediate is inlined, not built.
5. *(Optional)* `dbt docs generate && dbt docs serve` for the lineage site; `dbt snapshot` to re-capture history after a data change.

> **Schema routing** comes from `macros/generate_schema_name.sql`: seeds go to a bare
> `raw` schema; every other model is prefixed with the target schema
> (`dev` + `stg` → `dev_stg`, `dev` + `marts` → `dev_marts`; under the `prod` target,
> `prod_stg`, `prod_marts`, …). Models with no `+schema` stay in the target schema.
