# A/B Test Analysis: Early Delinquency Intervention

An end-to-end servicing analytics project that measures whether a personalized SMS and email outreach sequence improves payment recovery rates among early-stage delinquent borrowers. Built with Snowflake, dbt, Python, and Tableau Public.

---

## Verdict: SHIP IT

The treatment outreach lifted payment recovery by **8.67 percentage points** (from 43.89% to 52.56%), with a z-score of 13.89. The result is statistically significant at the 99.9% confidence level and holds consistently across all FICO tiers. The guardrail metric (severe delinquency) actually improved in the treatment group, meaning the intervention did not push borrowers deeper into default.

---

## Business Context

A fintech lender runs outreach experiments on borrowers who are 16 to 120 days past due. The goal is to find contact strategies that recover more payments before loans roll into severe delinquency or charge-off. This project simulates the full analytical lifecycle of one such experiment:

- A **control group** received a standard one-touch email reminder
- A **treatment group** received a personalized SMS and email sequence timed to their payment history

The dataset is built on 25,856 real delinquent borrowers from the public LendingClub loan dataset (2007 to 2018), with a synthetic experiment overlay applied to simulate what a live A/B test would produce.

---

## Results

### Primary Metric: Payment Recovery Rate

| Group | Sample Size | Payment Rate | Severe Delinquency Rate |
|-------|------------|--------------|------------------------|
| Control | 12,903 | 43.89% | 19.25% |
| Treatment | 12,900 | 52.56% | 15.52% |

| Stat | Value |
|------|-------|
| Absolute lift | +8.67 percentage points |
| Relative lift | +19.75% |
| Z-score | 13.89 |
| 95% Confidence interval | [7.45pp, 9.89pp] |
| Statistically significant | Yes (p < 0.0001) |
| Guardrail check | Passed (severe delinquency fell by 3.73pp) |

### Segment Breakdown by FICO Tier

The lift is consistent across all credit score segments, which strengthens confidence in the result. This is not a subgroup-driven effect.

| FICO Tier | Control Rate | Treatment Rate | Lift |
|-----------|-------------|----------------|------|
| Prime (750+) | 51.89% | 60.35% | +8.46pp |
| Near-Prime (670-749) | 45.38% | 53.85% | +8.47pp |
| Subprime (below 670) | 36.18% | 45.63% | +9.45pp |

---

## Architecture

```
LendingClub CSV (Kaggle, 2007-2018, 2.2M loans)
        |
        v
Python script (pandas)
  Filters to 25,856 delinquent borrowers
  Assigns experiment groups (50/50 stratified by FICO)
  Generates Snowflake-ready SQL
        |
        v
Snowflake: AB_TEST_DB.RAW.raw_experiment_events
        |
        v
dbt staging: stg_experiment_events
  Deduplication, type casting, group standardization
        |
        v
dbt intermediate: int_experiment_metrics
  FICO tiers, balance tiers, risk flags, effective recovery
        |
        v
dbt marts: fct_ab_test_results
  Z-score, confidence intervals, lift, guardrail check, verdict
        |
        v
Tableau Public Dashboard
```

---

## Statistical Methodology

- **Test type:** Two-proportion z-test (appropriate for binary conversion outcomes)
- **Primary metric:** Payment recovery rate within the observation window
- **Guardrail metric:** Roll-to-severe delinquency rate (60+ days past due)
- **Significance threshold:** p < 0.05, two-tailed (z > 1.96)
- **Assignment method:** 50/50 stratified randomization by FICO bucket to ensure balance across credit tiers
- **Data quality checks:** Deduplication by borrower ID, null filtering, experiment group standardization

The z-score of 13.89 is well above the 1.96 threshold. This means the probability of observing a lift this large by random chance is effectively zero. The confidence interval of [7.45pp, 9.89pp] does not cross zero, confirming the direction of the effect is real.

---

## Data Quality

The raw dataset was intentionally seeded with real-world data issues to demonstrate cleaning logic in the dbt pipeline:

- 40 duplicate borrower records
- 25 rows with null values in key fields (FICO score, loan amount, annual income)
- 15 rows with malformed experiment group labels (e.g. "TREATMENT", "ctrl", " treatment ", "TrEaTmEnT")

The staging model handles all of these through deduplication, null filtering, and TRIM/LOWER normalization.

---

## How to Reproduce

**Requirements:** Python 3.10+, a free Snowflake trial account, dbt-snowflake

```bash
# 1. Clone the repo
git clone https://github.com/ravite7a/LendingClub_Snowflake_dbt.git
cd LendingClub_Snowflake_dbt

# 2. Install Python dependencies
pip install pandas numpy

# 3. Download the LendingClub dataset from Kaggle
# https://kaggle.com/datasets/wordsforthewise/lending-club
# Place accepted_2007_to_2018Q4.csv.gz in the data/ folder

# 4. Generate the Snowflake SQL
python data/01_prepare_data.py

# 5. Load into Snowflake (using SnowSQL CLI)
snowsql -a YOUR_ACCOUNT -u YOUR_USERNAME -f snowflake/01_raw_schema.sql

# 6. Run the dbt pipeline
cd dbt
dbt run
dbt test

# 7. Run the analysis queries in your Snowflake worksheet
# analysis/statistical_analysis.sql
```

---

## Project Structure

```
.
+-- data/
|   +-- 01_prepare_data.py       # Filters raw data, assigns groups, writes SQL
+-- snowflake/
|   +-- 01_raw_schema.sql        # DDL and INSERT statements for Snowflake
+-- dbt/
|   +-- dbt_project.yml
|   +-- models/
|       +-- staging/             # stg_experiment_events (view)
|       +-- intermediate/        # int_experiment_metrics (view)
|       +-- marts/               # fct_ab_test_results (table)
+-- analysis/
|   +-- statistical_analysis.sql # Final analysis queries
+-- dashboard/                   # Tableau workbook
```

---

## Tools

| Tool | Purpose |
|------|---------|
| Python + pandas | Data preparation and SQL generation |
| Snowflake | Cloud data warehouse |
| dbt Core | Data transformation pipeline |
| Tableau Public | Executive dashboard |
| GitHub | Version control and portfolio hosting |

---

## Interview Talking Points

**Why a z-test instead of a t-test?** The outcome (payment made: yes/no) is a binary proportion, not a continuous variable. The two-proportion z-test is the correct test for comparing conversion rates between two groups.

**What is a guardrail metric?** A secondary metric that monitors for harm. Even if the primary metric improves, the experiment fails if the guardrail worsens beyond a tolerance threshold. Here, we required that severe delinquency in the treatment group not exceed 5% above the control rate. Treatment actually improved on this metric.

**What would you do if p-value came back at 0.06?** I would not ship the change. A result at 0.06 means roughly a 1 in 17 chance of a false positive, which is above the agreed threshold. The right call is to run the experiment longer to accumulate more statistical power, not to lower the bar.

**What is statistical power?** Power is the probability of detecting a real effect when one exists. A power of 80% means that if the treatment truly works, you have an 80% chance of getting a statistically significant result. Low power leads to false negatives. You calculate required sample size before running the experiment using the expected effect size and desired power.
