import pandas as pd
import numpy as np
import random
import os

# ── CONFIG ────────────────────────────────────────────────────────────
INPUT_FILE = 'data/accepted_2007_to_2018Q4.csv.gz'
OUTPUT_FILE = 'snowflake/01_raw_schema.sql'
RANDOM_SEED = 42
np.random.seed(RANDOM_SEED)
random.seed(RANDOM_SEED)

# ── LOAD & FILTER ─────────────────────────────────────────────────────
print('Loading dataset... (this may take 30-60 seconds)')
cols = ['id', 'loan_amnt', 'loan_status', 'int_rate', 'dti',
        'fico_range_low', 'annual_inc', 'delinq_2yrs',
        'recoveries', 'addr_state', 'issue_d']
df = pd.read_csv(INPUT_FILE, usecols=cols, low_memory=False)
print(f'Total rows loaded: {len(df):,}')

delinq = df[df['loan_status'].isin([
    'Late (16-30 days)', 'Late (31-120 days)'
])].copy()
print(f'Delinquent borrowers: {len(delinq):,}')

# ── CLEAN ─────────────────────────────────────────────────────────────
delinq['fico_range_low'] = pd.to_numeric(delinq['fico_range_low'], errors='coerce')
delinq['loan_amnt']      = pd.to_numeric(delinq['loan_amnt'],      errors='coerce')
delinq['int_rate']       = pd.to_numeric(
    delinq['int_rate'].astype(str).str.replace('%', ''), errors='coerce')
delinq['dti']            = pd.to_numeric(delinq['dti'],            errors='coerce')
delinq['annual_inc']     = pd.to_numeric(delinq['annual_inc'],     errors='coerce')
delinq['delinq_2yrs']    = pd.to_numeric(delinq['delinq_2yrs'],    errors='coerce')
delinq['recoveries']     = pd.to_numeric(delinq['recoveries'],     errors='coerce').fillna(0)

# ── FICO BUCKET for stratified assignment ─────────────────────────────
def fico_bucket(score):
    if pd.isna(score):  return 'unknown'
    if score >= 750:    return 'prime'
    if score >= 670:    return 'near_prime'
    return 'subprime'

delinq['fico_bucket'] = delinq['fico_range_low'].apply(fico_bucket)

# ── EXPERIMENT GROUP (50/50 stratified by FICO bucket) ────────────────
delinq['experiment_group'] = ''
for bucket in delinq['fico_bucket'].unique():
    idx = delinq[delinq['fico_bucket'] == bucket].index
    assignments = (['control'] * (len(idx) // 2) +
                   ['treatment'] * (len(idx) - len(idx) // 2))
    random.shuffle(assignments)
    delinq.loc[idx, 'experiment_group'] = assignments

# ── PAYMENT MADE FLAG ─────────────────────────────────────────────────
def pay_prob(row):
    base = 0.40
    if row['fico_bucket'] == 'prime':      base += 0.15
    elif row['fico_bucket'] == 'near_prime': base += 0.07
    if row['experiment_group'] == 'treatment': base += 0.08
    if pd.notna(row['loan_amnt']) and row['loan_amnt'] > 20000: base -= 0.05
    return min(max(base, 0.05), 0.95)

delinq['pay_prob'] = delinq.apply(pay_prob, axis=1)
delinq['payment_made_flag'] = (np.random.uniform(size=len(delinq))
                                < delinq['pay_prob']).astype(int)

# ── ROLLED TO SEVERE FLAG ─────────────────────────────────────────────
def severe_prob(row):
    if row['payment_made_flag'] == 1: return 0.02
    base = 0.30
    if row['fico_bucket'] == 'subprime':       base += 0.15
    if row['experiment_group'] == 'treatment': base -= 0.03
    return min(max(base, 0.05), 0.90)

delinq['severe_prob'] = delinq.apply(severe_prob, axis=1)
delinq['rolled_to_severe_flag'] = (np.random.uniform(size=len(delinq))
                                    < delinq['severe_prob']).astype(int)

# ── INJECT INTENTIONAL MESS ───────────────────────────────────────────
dupes = delinq.sample(40, random_state=1)
delinq = pd.concat([delinq, dupes]).reset_index(drop=True)

null_idx = delinq.sample(25, random_state=2).index
for col in ['fico_range_low', 'loan_amnt', 'annual_inc']:
    delinq.loc[null_idx[:8], col] = np.nan

bad_idx = delinq.sample(15, random_state=3).index
bad_vals = ['Control', 'TREATMENT', 'ctrl', 'treat', ' treatment ',
            'TrEaTmEnT', 'CTRL', 'treatment ', 'control ', 'Treatment',
            'Control ', 'treatmnt', 'controI', 'CONTROL ', ' control']
for i, idx in enumerate(bad_idx):
    delinq.loc[idx, 'experiment_group'] = bad_vals[i]

print(f'Final rows (including intentional mess): {len(delinq):,}')

# ── WRITE SQL ─────────────────────────────────────────────────────────
os.makedirs('snowflake', exist_ok=True)

def esc(v):
    if pd.isna(v):          return 'NULL'
    if isinstance(v, str):  return "'" + str(v).replace("'", "''") + "'"
    return str(v)

with open(OUTPUT_FILE, 'w') as f:
    f.write('-- DDL\n')
    f.write('CREATE DATABASE IF NOT EXISTS AB_TEST_DB;\n')
    f.write('USE DATABASE AB_TEST_DB;\n')
    f.write('CREATE SCHEMA IF NOT EXISTS RAW;\n')
    f.write('USE SCHEMA RAW;\n\n')
    f.write('''CREATE OR REPLACE TABLE raw_experiment_events (
    borrower_id        VARCHAR,
    loan_balance       FLOAT,
    loan_status        VARCHAR,
    int_rate           FLOAT,
    debt_to_income     FLOAT,
    credit_score       FLOAT,
    annual_income      FLOAT,
    prior_delinquency  FLOAT,
    recovery_amount    FLOAT,
    state              VARCHAR,
    cohort_date        VARCHAR,
    experiment_group   VARCHAR,
    payment_made_flag  INT,
    rolled_to_severe   INT
);\n\n''')

    chunk = 500
    for i in range(0, len(delinq), chunk):
        batch = delinq.iloc[i:i + chunk]
        vals = []
        for _, row in batch.iterrows():
            v = (
                f"({esc(row['id'])},{esc(row['loan_amnt'])},"
                f"{esc(row['loan_status'])},{esc(row['int_rate'])},"
                f"{esc(row['dti'])},{esc(row['fico_range_low'])},"
                f"{esc(row['annual_inc'])},{esc(row['delinq_2yrs'])},"
                f"{esc(row['recoveries'])},{esc(row['addr_state'])},"
                f"{esc(row['issue_d'])},{esc(row['experiment_group'])},"
                f"{esc(row['payment_made_flag'])},{esc(row['rolled_to_severe_flag'])})"
            )
            vals.append(v)
        f.write('INSERT INTO raw_experiment_events VALUES\n')
        f.write(',\n'.join(vals) + ';\n\n')
        if i % 5000 == 0:
            print(f'  Written {i:,} rows...')

print(f'Done! SQL file written to: {OUTPUT_FILE}')
