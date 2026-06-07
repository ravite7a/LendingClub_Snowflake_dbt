-- ══════════════════════════════════════════════════════
-- FINAL STATISTICAL ANALYSIS
-- A/B Test: Early Delinquency Intervention
-- ══════════════════════════════════════════════════════

USE DATABASE AB_TEST_DB;
USE SCHEMA RAW_MARTS;

-- ── 1. Top-level results ──────────────────────────────
SELECT
    'CONTROL'                   AS group_name,
    n_ctrl                      AS sample_size,
    payment_rate_control        AS payment_rate,
    severe_rate_control         AS severe_delinquency_rate,
    avg_recovery_ctrl           AS avg_recovery_dollars
FROM fct_ab_test_results
UNION ALL
SELECT
    'TREATMENT',
    n_trt,
    payment_rate_treatment,
    severe_rate_treatment,
    avg_recovery_trt
FROM fct_ab_test_results;

-- ── 2. Statistical evidence ───────────────────────────
SELECT
    absolute_lift,
    relative_lift_pct,
    z_score,
    statistically_significant,
    ci_lower,
    ci_upper,
    verdict
FROM fct_ab_test_results;

-- ── 3. Economic impact ────────────────────────────────
SELECT
    total_recovery_trt - total_recovery_ctrl    AS incremental_dollars_recovered,
    avg_recovery_trt   - avg_recovery_ctrl      AS avg_incremental_recovery_per_borrower
FROM fct_ab_test_results;

-- ── 4. Segment breakdown (by FICO tier) ──────────────
SELECT
    fico_tier,
    experiment_group,
    COUNT(*)                                    AS n,
    ROUND(AVG(payment_made_flag::FLOAT), 4)     AS payment_rate,
    ROUND(AVG(rolled_to_severe::FLOAT), 4)      AS severe_rate
FROM AB_TEST_DB.RAW_INTERMEDIATE.int_experiment_metrics
GROUP BY 1, 2
ORDER BY 1, 2;
