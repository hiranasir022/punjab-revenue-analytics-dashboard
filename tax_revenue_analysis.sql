-- ============================================================
-- Tax Revenue Analysis in SQL (PostgreSQL)
-- Punjab Excise & Taxation Department, public data
-- Run this in psql (PostgreSQL).
-- ============================================================

-- ------------------------------------------------------------
-- SETUP: create tables, then load the CSVs with \copy (a psql command).
-- Run the two CREATE TABLE statements first, then the two \copy lines.
-- Put the correct file path if the CSVs are not in psql's current folder.
-- ------------------------------------------------------------

DROP TABLE IF EXISTS revenue;
CREATE TABLE revenue (
    fiscal_year                    TEXT,
    levy_name                      TEXT,
    target_rs_million              NUMERIC,
    achieved_rs_million            NUMERIC,
    achieved_prev_year_rs_million  NUMERIC,
    growth_vs_last_year_pct        NUMERIC,
    achievement_vs_target_pct      NUMERIC
);

DROP TABLE IF EXISTS district_reg;
CREATE TABLE district_reg (
    quarter                    TEXT,
    district                   TEXT,
    total_vehicles_registered  INTEGER
);

-- Load the data (run these in psql):
-- \copy revenue       FROM '01_Provincial_Revenue_2015-2024.csv'        WITH (FORMAT csv, HEADER true);
-- \copy district_reg  FROM '02_District_Vehicle_Registration_long.csv'  WITH (FORMAT csv, HEADER true);

-- ============================================================
-- 1. Total revenue collected per levy (all years)
-- ============================================================
SELECT levy_name,
       ROUND(SUM(achieved_rs_million), 3) AS total_rs_million
FROM revenue
GROUP BY levy_name
ORDER BY total_rs_million DESC;

-- ============================================================
-- 2. Achieved revenue by levy and fiscal year (three largest levies)
--    A CASE pivot: one column per levy.
-- ============================================================
SELECT fiscal_year,
       ROUND(SUM(CASE WHEN levy_name = 'Motor Vehicle Tax' THEN achieved_rs_million END), 1) AS motor_vehicle_tax,
       ROUND(SUM(CASE WHEN levy_name = 'Property Tax'      THEN achieved_rs_million END), 1) AS property_tax,
       ROUND(SUM(CASE WHEN levy_name = 'Excise Duty'       THEN achieved_rs_million END), 1) AS excise_duty
FROM revenue
GROUP BY fiscal_year
ORDER BY fiscal_year;

-- ============================================================
-- 3. Concentration: share of the two largest levies each year
--    Shows the narrow tax base (two levies are 83% to 90%).
-- ============================================================
WITH yearly AS (
    SELECT fiscal_year,
           SUM(achieved_rs_million) AS total,
           SUM(CASE WHEN levy_name IN ('Motor Vehicle Tax', 'Property Tax')
                    THEN achieved_rs_million ELSE 0 END) AS two_largest
    FROM revenue
    GROUP BY fiscal_year
)
SELECT fiscal_year,
       ROUND(two_largest * 100.0 / total, 1) AS two_largest_share_pct
FROM yearly
ORDER BY fiscal_year;

-- ============================================================
-- 4. Year-on-year growth of the three largest levies
--    LAG() gets the previous year's value (Excel: =(C3-C2)/C2).
--    Note: 2016-17 is missing, so 2017-18 growth spans two years.
-- ============================================================
WITH big AS (
    SELECT fiscal_year, levy_name, achieved_rs_million
    FROM revenue
    WHERE levy_name IN ('Motor Vehicle Tax', 'Property Tax', 'Excise Duty')
)
SELECT fiscal_year, levy_name,
       ROUND(
           (achieved_rs_million - LAG(achieved_rs_million) OVER (PARTITION BY levy_name ORDER BY fiscal_year))
           * 100.0
           / LAG(achieved_rs_million) OVER (PARTITION BY levy_name ORDER BY fiscal_year)
       , 1) AS growth_pct
FROM big
ORDER BY levy_name, fiscal_year;

-- ============================================================
-- 5. Target accuracy: achievement against target, per levy
--    A large spread (min to max) means targets are unreliable.
--    Excise Duty swings from about 33% to 109%.
-- ============================================================
SELECT levy_name,
       COUNT(*)                                   AS years,
       ROUND(MIN(achievement_vs_target_pct), 1)   AS min_achievement_pct,
       ROUND(AVG(achievement_vs_target_pct), 1)   AS avg_achievement_pct,
       ROUND(MAX(achievement_vs_target_pct), 1)   AS max_achievement_pct
FROM revenue
WHERE levy_name IN ('Motor Vehicle Tax', 'Property Tax', 'Excise Duty')
GROUP BY levy_name;

-- ============================================================
-- 6. District disparity: average registrations per quarter and share
--    Lahore alone is about a quarter of all registrations.
-- ============================================================
WITH dist AS (
    SELECT district, AVG(total_vehicles_registered) AS avg_per_quarter
    FROM district_reg
    GROUP BY district
)
SELECT district,
       ROUND(avg_per_quarter, 0) AS avg_per_quarter,
       ROUND(avg_per_quarter * 100.0 / (SELECT SUM(avg_per_quarter) FROM dist), 2) AS share_pct
FROM dist
ORDER BY avg_per_quarter DESC;

-- ============================================================
-- 7. Share of the top 5 districts (concentration of activity)
-- ============================================================
WITH dist AS (
    SELECT district, AVG(total_vehicles_registered) AS avg_per_quarter
    FROM district_reg
    GROUP BY district
),
shares AS (
    SELECT district,
           avg_per_quarter * 100.0 / (SELECT SUM(avg_per_quarter) FROM dist) AS share_pct
    FROM dist
)
SELECT ROUND(SUM(share_pct), 1) AS top5_share_pct
FROM (SELECT share_pct FROM shares ORDER BY share_pct DESC LIMIT 5) t;

-- ============================================================
-- 8. Province-wide registrations per quarter (input to the forecast)
-- ============================================================
SELECT quarter,
       SUM(total_vehicles_registered) AS total_registrations
FROM district_reg
GROUP BY quarter
ORDER BY quarter;
