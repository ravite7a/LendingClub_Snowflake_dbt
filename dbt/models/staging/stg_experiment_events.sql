WITH source AS (
    SELECT * FROM {{ source('raw', 'raw_experiment_events') }}
),

deduplicated AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY borrower_id
            ORDER BY cohort_date DESC
        ) AS row_num
    FROM source
),

cleaned AS (
    SELECT
        borrower_id,
        loan_balance,
        loan_status,
        int_rate,
        debt_to_income,
        credit_score,
        annual_income,
        prior_delinquency,
        COALESCE(recovery_amount, 0) AS recovery_amount,
        state,
        cohort_date,
        TRIM(LOWER(experiment_group)) AS experiment_group,
        payment_made_flag,
        rolled_to_severe
    FROM deduplicated
    WHERE row_num = 1
      AND borrower_id IS NOT NULL
      AND loan_balance IS NOT NULL
      AND credit_score IS NOT NULL
      AND TRIM(LOWER(experiment_group)) IN ('control', 'treatment')
)

SELECT * FROM cleaned
