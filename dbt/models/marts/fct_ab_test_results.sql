WITH metrics AS (
    SELECT * FROM {{ ref('int_experiment_metrics') }}
),

group_stats AS (
    SELECT
        experiment_group,
        COUNT(*)                        AS n,
        SUM(payment_made_flag)          AS conversions,
        SUM(rolled_to_severe)           AS severe_count,
        AVG(payment_made_flag::FLOAT)   AS payment_rate,
        AVG(rolled_to_severe::FLOAT)    AS severe_rate,
        AVG(effective_recovery)         AS avg_recovery,
        SUM(effective_recovery)         AS total_recovery
    FROM metrics
    GROUP BY experiment_group
),

pivoted AS (
    SELECT
        MAX(CASE WHEN experiment_group = 'control'   THEN n END)            AS n_ctrl,
        MAX(CASE WHEN experiment_group = 'treatment' THEN n END)            AS n_trt,
        MAX(CASE WHEN experiment_group = 'control'   THEN conversions END)  AS conv_ctrl,
        MAX(CASE WHEN experiment_group = 'treatment' THEN conversions END)  AS conv_trt,
        MAX(CASE WHEN experiment_group = 'control'   THEN payment_rate END) AS rate_ctrl,
        MAX(CASE WHEN experiment_group = 'treatment' THEN payment_rate END) AS rate_trt,
        MAX(CASE WHEN experiment_group = 'control'   THEN severe_rate END)  AS severe_ctrl,
        MAX(CASE WHEN experiment_group = 'treatment' THEN severe_rate END)  AS severe_trt,
        MAX(CASE WHEN experiment_group = 'control'   THEN avg_recovery END) AS avg_rec_ctrl,
        MAX(CASE WHEN experiment_group = 'treatment' THEN avg_recovery END) AS avg_rec_trt,
        MAX(CASE WHEN experiment_group = 'control'   THEN total_recovery END) AS tot_rec_ctrl,
        MAX(CASE WHEN experiment_group = 'treatment' THEN total_recovery END) AS tot_rec_trt
    FROM group_stats
),

z_calc AS (
    SELECT *,
        (conv_ctrl + conv_trt) / (n_ctrl + n_trt) AS p_pool,
        rate_trt - rate_ctrl                        AS lift
    FROM pivoted
),

final AS (
    SELECT
        n_ctrl, n_trt, conv_ctrl, conv_trt,
        ROUND(rate_ctrl, 4)             AS payment_rate_control,
        ROUND(rate_trt,  4)             AS payment_rate_treatment,
        ROUND(lift, 4)                  AS absolute_lift,
        ROUND(lift / NULLIF(rate_ctrl, 0), 4) AS relative_lift_pct,

        -- z-score
        ROUND(
            lift / NULLIF(SQRT(p_pool * (1 - p_pool) * (1.0/n_ctrl + 1.0/n_trt)), 0)
        , 4) AS z_score,

        -- Significance flag
        CASE WHEN ABS(lift / NULLIF(SQRT(p_pool * (1 - p_pool) * (1.0/n_ctrl + 1.0/n_trt)), 0)) > 1.96
            THEN 'YES' ELSE 'NO'
        END AS statistically_significant,

        -- 95% confidence interval
        ROUND(lift - 1.96 * SQRT(p_pool*(1-p_pool)*(1.0/n_ctrl+1.0/n_trt)), 4) AS ci_lower,
        ROUND(lift + 1.96 * SQRT(p_pool*(1-p_pool)*(1.0/n_ctrl+1.0/n_trt)), 4) AS ci_upper,

        -- Guardrail
        ROUND(severe_ctrl, 4) AS severe_rate_control,
        ROUND(severe_trt,  4) AS severe_rate_treatment,

        -- Economics
        ROUND(avg_rec_ctrl, 2) AS avg_recovery_ctrl,
        ROUND(avg_rec_trt,  2) AS avg_recovery_trt,
        ROUND(tot_rec_ctrl, 2) AS total_recovery_ctrl,
        ROUND(tot_rec_trt,  2) AS total_recovery_trt,

        -- Verdict
        CASE
            WHEN ABS(lift / NULLIF(SQRT(p_pool*(1-p_pool)*(1.0/n_ctrl+1.0/n_trt)),0)) > 1.96
                AND lift > 0
                AND severe_trt <= severe_ctrl * 1.05
            THEN 'SHIP IT'
            WHEN ABS(lift / NULLIF(SQRT(p_pool*(1-p_pool)*(1.0/n_ctrl+1.0/n_trt)),0)) > 1.96
                AND lift < 0
            THEN 'DO NOT SHIP'
            ELSE 'RUN LONGER'
        END AS verdict

    FROM z_calc
)

SELECT * FROM final
