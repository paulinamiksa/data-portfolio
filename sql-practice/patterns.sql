-- =====================================================================
-- SQL patterns for data interviews (PostgreSQL)
-- Common problem types with a reusable template and a short explanation.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Rows without a match (anti-join)
--    "Pages with no likes", "customers who never ordered"
-- ---------------------------------------------------------------------
SELECT p.page_id
FROM pages p
LEFT JOIN page_likes l ON l.page_id = p.page_id
WHERE l.page_id IS NULL          -- no matching row on the right side
ORDER BY p.page_id;

-- Alternative with NOT EXISTS (often clearer and safe with NULLs)
SELECT p.page_id
FROM pages p
WHERE NOT EXISTS (
  SELECT 1 FROM page_likes l WHERE l.page_id = p.page_id
);


-- ---------------------------------------------------------------------
-- 2. Filter groups with HAVING
--    "Candidates who have ALL required skills"
--    WHERE filters rows before grouping, HAVING filters groups after.
-- ---------------------------------------------------------------------
SELECT candidate_id
FROM candidates
WHERE skill IN ('Python', 'Tableau', 'PostgreSQL')
GROUP BY candidate_id
HAVING COUNT(DISTINCT skill) = 3;


-- ---------------------------------------------------------------------
-- 3. Conditional aggregation: SUM(CASE WHEN ...)
--    "Laptop vs mobile views" - several counts in one query
-- ---------------------------------------------------------------------
SELECT
  SUM(CASE WHEN device_type = 'laptop' THEN 1 ELSE 0 END)              AS laptop_views,
  SUM(CASE WHEN device_type IN ('tablet', 'phone') THEN 1 ELSE 0 END)  AS mobile_views
FROM viewership;


-- ---------------------------------------------------------------------
-- 4. Rates and conversion (click-through rate, A/B test conversion)
--    Multiply by 100.0 (or cast) to avoid integer division.
-- ---------------------------------------------------------------------
SELECT
  app_id,
  ROUND(100.0 * SUM(CASE WHEN event_type = 'click' THEN 1 ELSE 0 END)
              / SUM(CASE WHEN event_type = 'impression' THEN 1 ELSE 0 END), 2) AS ctr
FROM events
WHERE EXTRACT(YEAR FROM timestamp) = 2022
GROUP BY app_id;

-- A/B test conversion per group (LEFT JOIN keeps users with no orders)
SELECT
  a.grp,
  COUNT(DISTINCT a.user_id)                                         AS users,
  COUNT(DISTINCT o.user_id)                                         AS buyers,
  ROUND(1.0 * COUNT(DISTINCT o.user_id) / COUNT(DISTINCT a.user_id), 4) AS conversion
FROM assignments a
LEFT JOIN orders o ON o.user_id = a.user_id
GROUP BY a.grp;


-- ---------------------------------------------------------------------
-- 5. Duplicates
--    Find them with GROUP BY + HAVING, remove them with ROW_NUMBER.
-- ---------------------------------------------------------------------
-- Find duplicates
SELECT company_id, title, description, COUNT(*) AS cnt
FROM job_listings
GROUP BY company_id, title, description
HAVING COUNT(*) > 1;

-- Keep only the latest record per customer
WITH ranked AS (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY updated_at DESC) AS rn
  FROM customers
)
SELECT * FROM ranked WHERE rn = 1;


-- ---------------------------------------------------------------------
-- 6. N-th row per group: ROW_NUMBER
--    "User's third transaction"
--    Window functions cannot be used in WHERE -> compute in a CTE first.
-- ---------------------------------------------------------------------
WITH numbered AS (
  SELECT user_id, spend, transaction_date,
         ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY transaction_date) AS rn
  FROM transactions
)
SELECT user_id, spend, transaction_date
FROM numbered
WHERE rn = 3;


-- ---------------------------------------------------------------------
-- 7. Top N per group: RANK / DENSE_RANK
--    "Top 2 highest-grossing products in each category"
--    ROW_NUMBER: 1,2,3,4 (always unique)
--    RANK:       1,2,2,4 (ties share a rank, then a gap)
--    DENSE_RANK: 1,2,2,3 (ties share a rank, no gap)
-- ---------------------------------------------------------------------
WITH product_spend AS (
  SELECT category, product, SUM(spend) AS total_spend
  FROM product_spend_raw
  WHERE EXTRACT(YEAR FROM transaction_date) = 2022
  GROUP BY category, product
),
ranked AS (
  SELECT *,
         RANK() OVER (PARTITION BY category ORDER BY total_spend DESC) AS rnk
  FROM product_spend
)
SELECT category, product, total_spend
FROM ranked
WHERE rnk <= 2
ORDER BY category, rnk;

-- Second highest salary (DENSE_RANK handles ties)
WITH ranked AS (
  SELECT salary, DENSE_RANK() OVER (ORDER BY salary DESC) AS drnk
  FROM employee
)
SELECT DISTINCT salary AS second_highest_salary
FROM ranked
WHERE drnk = 2;


-- ---------------------------------------------------------------------
-- 8. First value in a group
--    "Card launch success": issued amount in the launch month
-- ---------------------------------------------------------------------
WITH launches AS (
  SELECT card_name, issued_amount,
         ROW_NUMBER() OVER (PARTITION BY card_name
                            ORDER BY issue_year, issue_month) AS rn
  FROM monthly_cards_issued
)
SELECT card_name, issued_amount
FROM launches
WHERE rn = 1
ORDER BY issued_amount DESC;


-- ---------------------------------------------------------------------
-- 9. Rolling (moving) average
--    "3-day rolling average of tweets per user"
--    Rolling: last N rows        -> ROWS BETWEEN N-1 PRECEDING AND CURRENT ROW
--    Cumulative: from the start  -> ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
--    Note: ROWS counts rows, not days - aggregate to one row per day first
--    and fill missing dates if needed.
-- ---------------------------------------------------------------------
SELECT user_id, tweet_date,
       ROUND(AVG(tweet_count) OVER (
         PARTITION BY user_id
         ORDER BY tweet_date
         ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
       ), 2) AS rolling_avg_3d
FROM tweets;


-- ---------------------------------------------------------------------
-- 10. Previous value and growth: LAG
--     "Year-on-year growth rate"
-- ---------------------------------------------------------------------
WITH yearly AS (
  SELECT EXTRACT(YEAR FROM transaction_date) AS yr,
         product_id,
         SUM(spend) AS curr_year_spend
  FROM user_transactions
  GROUP BY EXTRACT(YEAR FROM transaction_date), product_id
)
SELECT yr, product_id, curr_year_spend,
       LAG(curr_year_spend) OVER (PARTITION BY product_id ORDER BY yr) AS prev_year_spend,
       ROUND(100.0 * (curr_year_spend
                      - LAG(curr_year_spend) OVER (PARTITION BY product_id ORDER BY yr))
             / LAG(curr_year_spend) OVER (PARTITION BY product_id ORDER BY yr), 2) AS yoy_rate
FROM yearly;


-- ---------------------------------------------------------------------
-- 11. Retention: active this month AND last month
--     "Active user retention" - correlated subquery with EXISTS
--     EXISTS is TRUE if the subquery returns at least one row.
-- ---------------------------------------------------------------------
SELECT EXTRACT(MONTH FROM curr.event_date) AS mth,
       COUNT(DISTINCT curr.user_id)       AS monthly_active_users
FROM user_actions curr
WHERE EXISTS (
        SELECT 1
        FROM user_actions prev
        WHERE prev.user_id = curr.user_id
          AND DATE_TRUNC('month', prev.event_date) =
              DATE_TRUNC('month', curr.event_date - INTERVAL '1 month')
      )
  AND DATE_TRUNC('month', curr.event_date) = DATE '2022-07-01'
GROUP BY EXTRACT(MONTH FROM curr.event_date);


-- ---------------------------------------------------------------------
-- 12. Share of total within a group
--     "Time spent sending vs opening snaps" - percentage per age bucket
-- ---------------------------------------------------------------------
SELECT b.age_bucket,
       ROUND(100.0 * SUM(a.time_spent) FILTER (WHERE a.activity_type = 'send')
             / SUM(a.time_spent), 2) AS send_perc,
       ROUND(100.0 * SUM(a.time_spent) FILTER (WHERE a.activity_type = 'open')
             / SUM(a.time_spent), 2) AS open_perc
FROM activities a
JOIN age_breakdown b ON b.user_id = a.user_id
WHERE a.activity_type IN ('send', 'open')
GROUP BY b.age_bucket;


-- ---------------------------------------------------------------------
-- 13. "Has all categories": COUNT(DISTINCT) compared to a total
--     "Supercloud customer" - bought from every product category
-- ---------------------------------------------------------------------
SELECT c.customer_id
FROM customer_contracts c
JOIN products p ON p.product_id = c.product_id
GROUP BY c.customer_id
HAVING COUNT(DISTINCT p.product_category) =
       (SELECT COUNT(DISTINCT product_category) FROM products);


-- ---------------------------------------------------------------------
-- 14. Dates
--     EXTRACT: one part as a number (year, month, day, dow, epoch)
--     DATE_TRUNC: round down to month/week but keep the year
--     Time difference in minutes: EXTRACT(EPOCH FROM b - a) / 60
-- ---------------------------------------------------------------------
SELECT EXTRACT(YEAR FROM order_date)  AS yr,
       EXTRACT(MONTH FROM order_date) AS mth,
       DATE_TRUNC('month', order_date) AS month_start,
       EXTRACT(EPOCH FROM delivered_at - order_date) / 60 AS minutes_to_deliver
FROM orders;


-- ---------------------------------------------------------------------
-- 15. Repeated events within a time window: LAG + time difference
--     "Repeated payments within 10 minutes" (fraud / data quality)
-- ---------------------------------------------------------------------
WITH ordered AS (
  SELECT *,
         LAG(transaction_timestamp) OVER (
           PARTITION BY merchant_id, credit_card_id, amount
           ORDER BY transaction_timestamp
         ) AS prev_ts
  FROM transactions
)
SELECT COUNT(*) AS payment_count
FROM ordered
WHERE EXTRACT(EPOCH FROM transaction_timestamp - prev_ts) / 60 <= 10;
