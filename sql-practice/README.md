# SQL practice

SQL interview practice in PostgreSQL, based on problems from [DataLemur](https://datalemur.com).

- [`patterns.sql`](patterns.sql) – 15 reusable patterns with short explanations: anti-joins, `HAVING`, conditional aggregation, conversion rates, duplicates, `ROW_NUMBER` / `RANK` / `DENSE_RANK`, rolling averages, `LAG`, retention with `EXISTS`, date functions and time windows.

## Topics covered

| Pattern | Typical question |
|---|---|
| Anti-join (`LEFT JOIN ... IS NULL`, `NOT EXISTS`) | Records without a match |
| `GROUP BY` + `HAVING` | Groups meeting a condition |
| `SUM(CASE WHEN ...)` | Several counts in one query |
| Rates | Click-through rate, A/B test conversion |
| Duplicates | Find and remove duplicate records |
| `ROW_NUMBER` | N-th or latest record per group |
| `RANK` / `DENSE_RANK` | Top N per group, N-th highest value |
| Rolling average | Moving averages over time |
| `LAG` | Previous value, year-on-year growth |
| `EXISTS` | Retention, active in consecutive months |
| `DATE_TRUNC`, `EXTRACT` | Grouping and filtering by dates |
