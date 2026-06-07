WITH staged AS (
    SELECT * FROM {{ ref('stg_experiment_events') }}
),

with_metrics AS (
    SELECT
        borrower_id,
        experiment_group,
        loan_balance,
        credit_score,
        debt_to_income,
        annual_income,
        prior_delinquency,
        recovery_amount,
        state,
        cohort_date,
        payment_made_flag,
        rolled_to_severe,

        -- FICO tier segmentation
        CASE
            WHEN credit_score >= 750 THEN 'Prime'
            WHEN credit_score >= 670 THEN 'Near-Prime'
            ELSE 'Subprime'
        END AS fico_tier,

        -- Loan balance tier
        CASE
            WHEN loan_balance >= 25000 THEN 'High Balance (25K+)'
            WHEN loan_balance >= 10000 THEN 'Mid Balance (10-25K)'
            ELSE 'Low Balance (<10K)'
        END AS balance_tier,

        -- Recovery amount only for payers
        CASE
            WHEN payment_made_flag = 1 THEN recovery_amount
            ELSE 0
        END AS effective_recovery,

        -- High risk flag
        CASE
            WHEN credit_score < 620 OR debt_to_income > 35 OR prior_delinquency > 2
            THEN 1 ELSE 0
        END AS high_risk_flag

    FROM staged
)

SELECT * FROM with_metrics
