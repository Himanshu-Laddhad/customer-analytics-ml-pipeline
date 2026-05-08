-- ============================================================
-- RFM Feature Queries
-- Source table : transactions  (outputs/retail_clean.parquet)
-- Snapshot date: MAX(InvoiceDate) in the dataset (~2011-12-09)
-- All queries end with ';' so the notebook can split on ';\n'
-- ============================================================


-- ============================================================
-- Query 1: RFM Base
-- Per-customer recency, frequency, monetary value.
--   recency   = days between last purchase and snapshot date
--   frequency = count of distinct invoices
--   monetary  = total revenue (Quantity * Price)
-- ============================================================
WITH snapshot AS (
    SELECT MAX(InvoiceDate) AS snapshot_date
    FROM transactions
)
SELECT
    t."Customer ID"                                        AS customer_id,
    DATEDIFF('day', MAX(t.InvoiceDate), s.snapshot_date)  AS recency,
    COUNT(DISTINCT t.Invoice)                              AS frequency,
    SUM(t.Quantity * t.Price)                              AS monetary
FROM transactions t
CROSS JOIN snapshot s
GROUP BY t."Customer ID", s.snapshot_date
ORDER BY customer_id
;

-- ============================================================
-- Query 2: Extended Features
-- Joins extended behavioural features onto the RFM base.
--   aov               = monetary / frequency (avg order value)
--   purchase_velocity = invoices per day of customer lifetime
--   days_as_customer  = days between first and last purchase
--   unique_products   = distinct StockCodes purchased
--   unique_countries  = distinct countries (usually 1)
-- Self-contained: re-derives rfm_base internally via CTEs.
-- ============================================================
WITH snapshot AS (
    SELECT MAX(InvoiceDate) AS snapshot_date
    FROM transactions
),
rfm_base AS (
    SELECT
        t."Customer ID"                                        AS customer_id,
        DATEDIFF('day', MAX(t.InvoiceDate), s.snapshot_date)  AS recency,
        COUNT(DISTINCT t.Invoice)                              AS frequency,
        SUM(t.Quantity * t.Price)                              AS monetary
    FROM transactions t
    CROSS JOIN snapshot s
    GROUP BY t."Customer ID", s.snapshot_date
),
extended AS (
    SELECT
        "Customer ID"                                          AS customer_id,
        SUM(Quantity * Price) / COUNT(DISTINCT Invoice)       AS aov,
        COUNT(DISTINCT Invoice)::DOUBLE
            / (DATEDIFF('day', MIN(InvoiceDate), MAX(InvoiceDate)) + 1)
                                                              AS purchase_velocity,
        DATEDIFF('day', MIN(InvoiceDate), MAX(InvoiceDate))   AS days_as_customer,
        COUNT(DISTINCT StockCode)                              AS unique_products,
        COUNT(DISTINCT Country)                                AS unique_countries
    FROM transactions
    GROUP BY "Customer ID"
)
SELECT
    r.customer_id,
    r.recency,
    r.frequency,
    r.monetary,
    e.aov,
    e.purchase_velocity,
    e.days_as_customer,
    e.unique_products,
    e.unique_countries
FROM rfm_base  r
JOIN extended  e USING (customer_id)
ORDER BY customer_id
;

-- ============================================================
-- Query 3: Temporal Split Marker
-- Tags every customer with the observation / prediction window
-- boundaries used for train/test construction downstream.
--   observation_end  = '2010-12-01'  (training feature cutoff)
--   prediction_start = '2010-12-01'
--   prediction_end   = MAX(InvoiceDate) in the dataset
-- RFM features should be recomputed on data < observation_end
-- when building the actual train set in the modelling notebook.
-- ============================================================
WITH snapshot AS (
    SELECT MAX(InvoiceDate) AS snapshot_date
    FROM transactions
),
rfm_base AS (
    SELECT
        t."Customer ID"                                        AS customer_id,
        DATEDIFF('day', MAX(t.InvoiceDate), s.snapshot_date)  AS recency,
        COUNT(DISTINCT t.Invoice)                              AS frequency,
        SUM(t.Quantity * t.Price)                              AS monetary
    FROM transactions t
    CROSS JOIN snapshot s
    GROUP BY t."Customer ID", s.snapshot_date
)
SELECT
    r.customer_id,
    r.recency,
    r.frequency,
    r.monetary,
    CAST('2010-12-01' AS DATE)         AS observation_end,
    CAST('2010-12-01' AS DATE)         AS prediction_start,
    CAST(s.snapshot_date AS DATE)      AS prediction_end
FROM rfm_base r
CROSS JOIN snapshot s
ORDER BY customer_id
;
