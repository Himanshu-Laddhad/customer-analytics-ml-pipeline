-- ============================================================
-- RFM Feature Queries
-- Source table : transactions  (outputs/retail_clean.parquet)
-- Observation window : InvoiceDate < 2010-12-01  (features only)
-- Snapshot date      : 2010-12-01  (recency reference point)
-- All queries end with ';' so the notebook can split on ';\n'
-- ============================================================


-- ============================================================
-- Query 1: RFM Base
-- Per-customer recency, frequency, monetary value.
--   recency   = days between last obs-window purchase and 2010-12-01
--   frequency = distinct invoices in observation window
--   monetary  = total revenue in observation window
-- Only transactions before 2010-12-01 are included to prevent
-- leakage from the prediction window used to define churn labels.
-- ============================================================
WITH snapshot AS (
    SELECT TIMESTAMP '2010-12-01 00:00:00' AS snapshot_date
)
SELECT
    t."Customer ID"                                        AS customer_id,
    DATEDIFF('day', MAX(t.InvoiceDate), s.snapshot_date)  AS recency,
    COUNT(DISTINCT t.Invoice)                              AS frequency,
    SUM(t.Quantity * t.Price)                              AS monetary
FROM transactions t
CROSS JOIN snapshot s
WHERE t.InvoiceDate < TIMESTAMP '2010-12-01 00:00:00'
GROUP BY t."Customer ID", s.snapshot_date
ORDER BY customer_id
;

-- ============================================================
-- Query 2: Extended Features
-- Joins extended behavioural features onto the RFM base.
--   aov               = monetary / frequency (avg order value)
--   purchase_velocity = invoices per day of customer lifetime
--   days_as_customer  = days between first and last obs-window purchase
--   unique_products   = distinct StockCodes in observation window
--   unique_countries  = distinct countries (usually 1)
-- All CTEs filter to InvoiceDate < 2010-12-01 to prevent leakage.
-- Self-contained: re-derives rfm_base internally via CTEs.
-- ============================================================
WITH snapshot AS (
    SELECT TIMESTAMP '2010-12-01 00:00:00' AS snapshot_date
),
rfm_base AS (
    SELECT
        t."Customer ID"                                        AS customer_id,
        DATEDIFF('day', MAX(t.InvoiceDate), s.snapshot_date)  AS recency,
        COUNT(DISTINCT t.Invoice)                              AS frequency,
        SUM(t.Quantity * t.Price)                              AS monetary
    FROM transactions t
    CROSS JOIN snapshot s
    WHERE t.InvoiceDate < TIMESTAMP '2010-12-01 00:00:00'
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
    WHERE InvoiceDate < TIMESTAMP '2010-12-01 00:00:00'
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
--   prediction_end   = MAX(InvoiceDate) in the full dataset
-- RFM features are already scoped to < observation_end above.
-- ============================================================
WITH snapshot AS (
    SELECT TIMESTAMP '2010-12-01 00:00:00' AS snapshot_date
),
rfm_base AS (
    SELECT
        t."Customer ID"                                        AS customer_id,
        DATEDIFF('day', MAX(t.InvoiceDate), s.snapshot_date)  AS recency,
        COUNT(DISTINCT t.Invoice)                              AS frequency,
        SUM(t.Quantity * t.Price)                              AS monetary
    FROM transactions t
    CROSS JOIN snapshot s
    WHERE t.InvoiceDate < TIMESTAMP '2010-12-01 00:00:00'
    GROUP BY t."Customer ID", s.snapshot_date
)
SELECT
    r.customer_id,
    r.recency,
    r.frequency,
    r.monetary,
    CAST('2010-12-01' AS DATE)                               AS observation_end,
    CAST('2010-12-01' AS DATE)                               AS prediction_start,
    CAST((SELECT MAX(InvoiceDate) FROM transactions) AS DATE) AS prediction_end
FROM rfm_base r
ORDER BY customer_id
;
