-- =============================================================================
-- Patient Targeting Demo: Setup Script
-- =============================================================================
-- Creates synthetic pharmacy data for patient adherence targeting.
-- Data structure mirrors real-world pharmacy benefit manager tables:
--   - Patient demographics and clinical characteristics
--   - Prescription fill history across therapeutic classes
--   - Manufacturer-funded adherence programs (one per drug/therapeutic area)
--   - Program outcomes (did the patient get a fill after intervention?)
--
-- Run this script in a Snowflake worksheet or via SnowSQL before opening the lab notebook.
-- =============================================================================

-- ─── Environment ────────────────────────────────────────────────────────────

CREATE OR REPLACE DATABASE PATIENT_TARGETING_DEMO;

CREATE OR REPLACE WAREHOUSE PATIENT_TARGETING_WH
    WAREHOUSE_SIZE = 'MEDIUM'
    AUTO_SUSPEND = 120
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

-- Compute pool for ML Jobs (XGBoost training runs here)
CREATE COMPUTE POOL IF NOT EXISTS PATIENT_TARGETING_POOL
    MIN_NODES = 1
    MAX_NODES = 1
    INSTANCE_FAMILY = CPU_X64_S
    AUTO_RESUME = TRUE
    AUTO_SUSPEND_SECS = 300;

USE WAREHOUSE PATIENT_TARGETING_WH;
USE DATABASE PATIENT_TARGETING_DEMO;

CREATE SCHEMA RAW;
CREATE SCHEMA FEATURE_STORE;
CREATE SCHEMA MODELS;
CREATE SCHEMA SCORING;
CREATE SCHEMA MONITORING;

CREATE OR REPLACE STAGE MODELS.SKILL_STAGE
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

USE SCHEMA RAW;

-- ─── 1. PATIENT_UNIVERSE (50,000 patients) ─────────────────────────────────
-- Mirrors RedSail's patient characteristics table:
--   - Hashed patient ID, age, payer type
--   - Zip-based median household income, urbanicity
--   - Rolling PDC across all meds, number of active medications
--   - Diagnosis code availability flag (only ~40% have e-prescription diagnosis codes)

CREATE OR REPLACE TABLE PATIENT_UNIVERSE AS
WITH base AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS patient_id,
        ROUND(UNIFORM(18, 92, RANDOM(1))::FLOAT) AS age,
        CASE
            WHEN UNIFORM(0, 100, RANDOM(2)) < 45 THEN 'Commercial'
            WHEN UNIFORM(0, 100, RANDOM(3)) < 75 THEN 'Medicare'
            WHEN UNIFORM(0, 100, RANDOM(4)) < 90 THEN 'Medicaid'
            ELSE 'Cash'
        END AS payer_type,
        -- Zip-based median household income (correlated with payer type)
        GREATEST(20000, LEAST(200000,
            CASE
                WHEN UNIFORM(0, 100, RANDOM(2)) < 45 THEN ROUND(NORMAL(75000, 25000, RANDOM(5)))
                WHEN UNIFORM(0, 100, RANDOM(3)) < 75 THEN ROUND(NORMAL(50000, 18000, RANDOM(6)))
                WHEN UNIFORM(0, 100, RANDOM(4)) < 90 THEN ROUND(NORMAL(35000, 12000, RANDOM(7)))
                ELSE ROUND(NORMAL(45000, 20000, RANDOM(8)))
            END
        )) AS zip_median_income,
        -- Urbanicity
        CASE
            WHEN UNIFORM(0, 100, RANDOM(9)) < 35 THEN 'Urban'
            WHEN UNIFORM(0, 100, RANDOM(10)) < 75 THEN 'Suburban'
            ELSE 'Rural'
        END AS urbanicity,
        -- ~40% have diagnosis codes from e-prescriptions
        CASE WHEN UNIFORM(0, 100, RANDOM(11)) < 40 THEN TRUE ELSE FALSE END AS has_diagnosis_codes,
        -- Number of active medications (correlated with age)
        GREATEST(1, LEAST(15, ROUND(
            CASE
                WHEN UNIFORM(0, 100, RANDOM(2)) < 45 THEN NORMAL(3, 1.5, RANDOM(12))  -- younger commercial
                ELSE NORMAL(5, 2.5, RANDOM(13))  -- older/medicare
            END
        ))) AS num_active_meds,
        -- Rolling PDC across all meds (higher for engaged patients)
        GREATEST(0.10, LEAST(1.0,
            ROUND(NORMAL(0.65, 0.20, RANDOM(14))::NUMERIC, 2)
        )) AS rolling_pdc_all_meds,
        -- US region
        CASE
            WHEN UNIFORM(0, 100, RANDOM(15)) < 22 THEN 'Northeast'
            WHEN UNIFORM(0, 100, RANDOM(16)) < 50 THEN 'South'
            WHEN UNIFORM(0, 100, RANDOM(17)) < 75 THEN 'Midwest'
            ELSE 'West'
        END AS region,
        -- Number of diagnosis codes (if available)
        CASE
            WHEN UNIFORM(0, 100, RANDOM(11)) < 40
            THEN GREATEST(1, LEAST(12, ROUND(NORMAL(3, 2, RANDOM(18)))))
            ELSE 0
        END AS diagnosis_count,
        -- Chronic condition indicators (correlated with age and med count)
        CASE WHEN UNIFORM(0, 100, RANDOM(2)) < 45
             THEN (UNIFORM(0, 100, RANDOM(19)) < 20)  -- younger: 20% chronic
             ELSE (UNIFORM(0, 100, RANDOM(20)) < 55)  -- older: 55% chronic
        END AS has_chronic_condition,
        -- Polypharmacy flag (5+ meds)
        CASE WHEN GREATEST(1, LEAST(15, ROUND(
            CASE
                WHEN UNIFORM(0, 100, RANDOM(2)) < 45 THEN NORMAL(3, 1.5, RANDOM(12))
                ELSE NORMAL(5, 2.5, RANDOM(13))
            END
        ))) >= 5 THEN TRUE ELSE FALSE END AS polypharmacy_flag
    FROM TABLE(GENERATOR(ROWCOUNT => 50000))
)
SELECT
    'P' || LPAD(patient_id::STRING, 6, '0') AS patient_id,
    age::INT AS age,
    CASE
        WHEN age < 30 THEN '18-29'
        WHEN age < 45 THEN '30-44'
        WHEN age < 60 THEN '45-59'
        WHEN age < 75 THEN '60-74'
        ELSE '75+'
    END AS age_group,
    payer_type,
    zip_median_income::INT AS zip_median_income,
    CASE
        WHEN zip_median_income < 40000 THEN 'Low'
        WHEN zip_median_income < 70000 THEN 'Medium'
        WHEN zip_median_income < 100000 THEN 'High'
        ELSE 'Very High'
    END AS income_tier,
    urbanicity,
    has_diagnosis_codes,
    num_active_meds::INT AS num_active_meds,
    rolling_pdc_all_meds,
    region,
    diagnosis_count::INT AS diagnosis_count,
    has_chronic_condition,
    polypharmacy_flag
FROM base;


-- ─── 2. PRESCRIPTION_HISTORY (~250,000 fills over 18 months) ────────────────
-- Rx fill records across therapeutic classes (GPI-level).
-- Patients with more active meds generate more fill records.

CREATE OR REPLACE TABLE PRESCRIPTION_HISTORY AS
WITH raw_fills AS (
    SELECT
        p.patient_id,
        p.payer_type,
        p.num_active_meds,
        DATEADD('day', -UNIFORM(1, 540, RANDOM(30)), CURRENT_DATE()) AS fill_date,
        UNIFORM(1, 100, RANDOM(31)) AS gpi_rand,
        UNIFORM(0, 100, RANDOM(32)) AS supply_rand,
        UNIFORM(0, 100, RANDOM(38)) AS keep_rand
    FROM PATIENT_UNIVERSE p,
         TABLE(GENERATOR(ROWCOUNT => 6)) g
),
fills AS (
    SELECT
        patient_id,
        fill_date,
        CASE
            WHEN gpi_rand <= 20 THEN 'Cardiovascular'
            WHEN gpi_rand <= 35 THEN 'Diabetes'
            WHEN gpi_rand <= 48 THEN 'Respiratory'
            WHEN gpi_rand <= 58 THEN 'Mental Health'
            WHEN gpi_rand <= 67 THEN 'Pain Management'
            WHEN gpi_rand <= 75 THEN 'Oncology'
            WHEN gpi_rand <= 82 THEN 'Immunology'
            WHEN gpi_rand <= 88 THEN 'Gastrointestinal'
            WHEN gpi_rand <= 93 THEN 'Endocrine'
            WHEN gpi_rand <= 97 THEN 'Neurology'
            ELSE 'Dermatology'
        END AS gpi_therapeutic_class,
        CASE
            WHEN supply_rand < 70 THEN 30
            WHEN supply_rand < 90 THEN 90
            ELSE 14
        END AS days_supply,
        CASE payer_type
            WHEN 'Commercial' THEN GREATEST(5, ROUND(NORMAL(25, 15, RANDOM(34))::NUMERIC, 2))
            WHEN 'Medicare'   THEN GREATEST(0, ROUND(NORMAL(15, 10, RANDOM(35))::NUMERIC, 2))
            WHEN 'Medicaid'   THEN GREATEST(0, ROUND(NORMAL(5, 3, RANDOM(36))::NUMERIC, 2))
            ELSE GREATEST(10, ROUND(NORMAL(60, 30, RANDOM(37))::NUMERIC, 2))
        END AS copay_amount
    FROM raw_fills
    WHERE keep_rand < (40 + num_active_meds * 8)
)
SELECT
    patient_id,
    fill_date,
    gpi_therapeutic_class,
    gpi_therapeutic_class || '-' || LPAD(UNIFORM(1, 20, RANDOM(39))::STRING, 3, '0') AS ndc_code,
    days_supply,
    copay_amount,
    CASE WHEN DATEDIFF('day',
        LAG(fill_date) OVER (PARTITION BY patient_id, gpi_therapeutic_class ORDER BY fill_date),
        fill_date
    ) > 45 + days_supply THEN TRUE ELSE FALSE END AS is_lapsed_fill
FROM fills
ORDER BY patient_id, fill_date;


-- ─── 3. ADHERENCE_PROGRAMS (18 manufacturer-funded programs) ────────────────
-- Each program targets a specific therapeutic class / drug.
-- Program types mirror RedSail's structure:
--   - Secondary Adherence (lapsed patients, ~90% of programs)
--   - Support Services (copay/PA assistance)
--   - Primary Adherence (new-to-therapy retention)

CREATE OR REPLACE TABLE ADHERENCE_PROGRAMS (
    program_id INT,
    program_name STRING,
    program_type STRING,
    target_gpi_class STRING,
    manufacturer STRING,
    lapse_window_min_days INT,
    lapse_window_max_days INT,
    description STRING
);

INSERT INTO ADHERENCE_PROGRAMS VALUES
    -- Secondary Adherence programs (lapsed patients, the majority)
    (1,  'Lisinopril Restart',          'Secondary Adherence', 'Cardiovascular',  'Novartis',       45, 225, 'Re-engage lapsed ACE inhibitor patients'),
    (2,  'Metformin Re-engagement',     'Secondary Adherence', 'Diabetes',        'Merck',          45, 180, 'Bring back lapsed Type 2 diabetes patients'),
    (3,  'AirSupra Adherence',          'Secondary Adherence', 'Respiratory',     'AstraZeneca',    45, 225, 'Re-engage lapsed rescue inhaler patients'),
    (4,  'Eliquis Continuation',        'Secondary Adherence', 'Cardiovascular',  'Bristol-Myers',  45, 200, 'Re-engage lapsed anticoagulant patients'),
    (5,  'Humira Persistence',          'Secondary Adherence', 'Immunology',      'AbbVie',         30, 120, 'Re-engage lapsed biologic patients'),
    (6,  'Ozempic Re-engagement',       'Secondary Adherence', 'Diabetes',        'Novo Nordisk',   45, 180, 'Bring back lapsed GLP-1 patients'),
    (7,  'Atorvastatin Restart',        'Secondary Adherence', 'Cardiovascular',  'Pfizer',         45, 225, 'Re-engage lapsed statin patients'),
    (8,  'Sertraline Continuation',     'Secondary Adherence', 'Mental Health',   'Pfizer',         30, 150, 'Re-engage lapsed SSRI patients'),
    (9,  'Xarelto Persistence',         'Secondary Adherence', 'Cardiovascular',  'Janssen',        45, 200, 'Re-engage lapsed anticoagulant patients'),
    (10, 'Dupixent Re-engagement',      'Secondary Adherence', 'Immunology',      'Sanofi/Regen',   30, 120, 'Re-engage lapsed biologic patients'),
    (11, 'Jardiance Restart',           'Secondary Adherence', 'Diabetes',        'Lilly',          45, 180, 'Bring back lapsed SGLT2 patients'),
    (12, 'Gabapentin Continuation',     'Secondary Adherence', 'Pain Management', 'Pfizer',         30, 150, 'Re-engage lapsed pain management patients'),
    -- Support Services programs (copay/PA assistance)
    (13, 'Keytruda Support Services',   'Support Services',    'Oncology',        'Merck',          NULL, NULL, 'Copay and prior auth assistance for immunotherapy patients'),
    (14, 'Stelara Support Services',    'Support Services',    'Immunology',      'Janssen',        NULL, NULL, 'Copay and prior auth assistance for biologic patients'),
    (15, 'Entyvio Support Services',    'Support Services',    'Gastrointestinal','Takeda',         NULL, NULL, 'Copay and prior auth assistance for IBD patients'),
    -- Primary Adherence programs (new-to-therapy)
    (16, 'New Statin Onboarding',       'Primary Adherence',   'Cardiovascular',  'Pfizer',         NULL, NULL, 'Keep new statin patients adherent through first 90 days'),
    (17, 'New Diabetes Onboarding',     'Primary Adherence',   'Diabetes',        'Lilly',          NULL, NULL, 'Keep new diabetes patients adherent through first 90 days'),
    (18, 'New Antidepressant Onboard',  'Primary Adherence',   'Mental Health',   'Pfizer',         NULL, NULL, 'Keep new SSRI/SNRI patients adherent through first 90 days');


-- ─── 4. PROGRAM_OUTCOMES (~30,000 patient-program records) ──────────────────
-- For each program, a set of patients were enrolled and we track outcomes.
-- got_fill = TRUE means the patient responded (filled their prescription).
-- Response rates are correlated with patient characteristics to create
-- learnable signal for the ML model.

CREATE OR REPLACE TABLE PROGRAM_OUTCOMES AS
WITH
-- Step 1: Generate enrollments using HASH for per-patient-per-program deterministic sampling
program_patients AS (
    SELECT
        p.patient_id,
        prog.program_id,
        prog.program_name,
        prog.program_type,
        prog.target_gpi_class,
        DATEADD('day', -UNIFORM(30, 365, RANDOM(40)), CURRENT_DATE()) AS enrolled_date,
        CASE
            WHEN UNIFORM(0, 100, RANDOM(41)) < 50 THEN 'Phone'
            WHEN UNIFORM(0, 100, RANDOM(42)) < 80 THEN 'Text'
            ELSE 'Mail'
        END AS outreach_method,
        'C' || CEIL(UNIFORM(1, 4, RANDOM(43))::FLOAT)::INT AS cohort_id,
        p.age,
        p.payer_type,
        p.zip_median_income,
        p.urbanicity,
        p.num_active_meds,
        p.rolling_pdc_all_meds,
        p.has_chronic_condition,
        p.polypharmacy_flag,
        p.has_diagnosis_codes,
        p.income_tier
    FROM PATIENT_UNIVERSE p
    CROSS JOIN ADHERENCE_PROGRAMS prog
    WHERE
        -- HASH produces a deterministic value per (patient, program) pair
        ABS(HASH(p.patient_id, prog.program_id)) % 1000 < (
            CASE prog.program_type
                WHEN 'Secondary Adherence' THEN 45  -- ~2,250 patients per program
                WHEN 'Support Services'    THEN 35  -- ~1,750 patients per program
                WHEN 'Primary Adherence'   THEN 30  -- ~1,500 patients per program
            END
        )
),
-- Step 2: Calculate response probability based on patient characteristics
scored AS (
    SELECT
        *,
        CASE program_type
            WHEN 'Secondary Adherence' THEN 0.35
            WHEN 'Support Services'    THEN 0.45
            ELSE 0.55
        END
        + CASE WHEN zip_median_income > 100000 THEN 0.12 WHEN zip_median_income > 70000 THEN 0.07 WHEN zip_median_income > 40000 THEN 0.02 ELSE -0.05 END
        + CASE WHEN rolling_pdc_all_meds > 0.80 THEN 0.10 WHEN rolling_pdc_all_meds > 0.60 THEN 0.04 WHEN rolling_pdc_all_meds > 0.40 THEN -0.02 ELSE -0.08 END
        + CASE WHEN num_active_meds >= 5 THEN 0.06 WHEN num_active_meds >= 3 THEN 0.03 ELSE -0.02 END
        + CASE WHEN has_chronic_condition THEN 0.05 ELSE -0.02 END
        + CASE payer_type WHEN 'Commercial' THEN 0.04 WHEN 'Medicare' THEN 0.02 WHEN 'Medicaid' THEN -0.03 ELSE -0.08 END
        + CASE urbanicity WHEN 'Suburban' THEN 0.03 WHEN 'Urban' THEN 0.01 ELSE -0.04 END
        + CASE WHEN age BETWEEN 40 AND 65 THEN 0.04 WHEN age BETWEEN 30 AND 75 THEN 0.01 ELSE -0.03 END
        + NORMAL(0, 0.08, RANDOM(50))
        AS response_probability
    FROM program_patients
)
SELECT
    patient_id,
    program_id,
    program_name,
    program_type,
    target_gpi_class,
    cohort_id,
    enrolled_date,
    outreach_method,
    -- Outcome: did they fill based on response probability?
    UNIFORM(0.0, 1.0, RANDOM(51))::FLOAT < GREATEST(0.05, LEAST(0.95, response_probability)) AS got_fill,
    -- Days to fill (if they got one)
    CASE WHEN UNIFORM(0.0, 1.0, RANDOM(52))::FLOAT < GREATEST(0.05, LEAST(0.95, response_probability))
         THEN GREATEST(1, ROUND(NORMAL(18, 10, RANDOM(53))))
         ELSE NULL END AS days_to_fill,
    -- Pre-intervention PDC
    GREATEST(0.0, LEAST(1.0, ROUND(
        CASE program_type
            WHEN 'Secondary Adherence' THEN NORMAL(0.30, 0.15, RANDOM(54))
            WHEN 'Support Services'    THEN NORMAL(0.50, 0.20, RANDOM(55))
            ELSE NORMAL(0.05, 0.02, RANDOM(56))
        END::NUMERIC, 2
    ))) AS pre_intervention_pdc,
    -- Post-intervention PDC
    GREATEST(0.0, LEAST(1.0, ROUND(
        CASE WHEN UNIFORM(0.0, 1.0, RANDOM(57))::FLOAT < GREATEST(0.05, LEAST(0.95, response_probability))
            THEN NORMAL(0.70, 0.15, RANDOM(58))
            ELSE NORMAL(0.25, 0.15, RANDOM(59))
        END::NUMERIC, 2
    ))) AS post_intervention_pdc
FROM scored;


-- ─── 5. Agent Tool Stored Procedures ────────────────────────────────────────
-- These run with owner's rights on the warehouse, bypassing the code_execution
-- sandbox's RUNTIME_MANAGED scope restriction. The agent calls them as generic tools.

-- Tool 1: List available adherence programs with enrollment counts
CREATE OR REPLACE PROCEDURE PATIENT_TARGETING_DEMO.MODELS.LIST_PROGRAMS()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS
$$
def run(session):
    df = session.sql("""
        SELECT p.PROGRAM_NAME, p.PROGRAM_TYPE, p.TARGET_GPI_CLASS, p.MANUFACTURER,
               COUNT(o.PATIENT_ID) AS ENROLLED,
               ROUND(SUM(CASE WHEN o.GOT_FILL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS RESPONSE_RATE_PCT
        FROM PATIENT_TARGETING_DEMO.RAW.ADHERENCE_PROGRAMS p
        LEFT JOIN PATIENT_TARGETING_DEMO.RAW.PROGRAM_OUTCOMES o ON p.PROGRAM_ID = o.PROGRAM_ID
        GROUP BY p.PROGRAM_NAME, p.PROGRAM_TYPE, p.TARGET_GPI_CLASS, p.MANUFACTURER
        ORDER BY p.PROGRAM_TYPE, p.PROGRAM_NAME
    """).to_pandas()
    return df.to_dict('records')
$$;

-- Tool 2: List all feature columns from the Feature Store
CREATE OR REPLACE PROCEDURE PATIENT_TARGETING_DEMO.MODELS.LIST_FEATURES()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'snowflake-ml-python')
HANDLER = 'run'
AS
$$
from snowflake.ml.feature_store import FeatureStore

def run(session):
    fs = FeatureStore(session=session, database="PATIENT_TARGETING_DEMO", name="FEATURE_STORE",
                      default_warehouse="PATIENT_TARGETING_WH")
    feature_views = fs.list_feature_views().to_pandas()
    result = []
    for _, fv_row in feature_views.iterrows():
        fv = fs.get_feature_view(name=fv_row['NAME'], version=fv_row['VERSION'])
        fv_data = fs.read_feature_view(fv)
        columns = [c for c in fv_data.columns if c != 'PATIENT_ID']
        result.append({
            "feature_view": fv_row['NAME'],
            "version": fv_row['VERSION'],
            "description": fv_row.get('DESC', ''),
            "columns": columns
        })
    return result
$$;

-- Tool 3: Profile a program's responders vs non-responders
CREATE OR REPLACE PROCEDURE PATIENT_TARGETING_DEMO.MODELS.PROFILE_PROGRAM(program_name VARCHAR)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'snowflake-ml-python', 'numpy', 'pandas')
HANDLER = 'run'
AS
$$
import numpy as np
import pandas as pd
from snowflake.ml.feature_store import FeatureStore

def run(session, program_name):
    fs = FeatureStore(session=session, database="PATIENT_TARGETING_DEMO", name="FEATURE_STORE",
                      default_warehouse="PATIENT_TARGETING_WH")

    outcomes = session.sql(f"""
        SELECT PATIENT_ID, GOT_FILL
        FROM PATIENT_TARGETING_DEMO.RAW.PROGRAM_OUTCOMES
        WHERE PROGRAM_NAME = '{program_name}'
    """).to_pandas()

    responders = set(outcomes[outcomes['GOT_FILL'] == True]['PATIENT_ID'])
    non_responders = set(outcomes[outcomes['GOT_FILL'] == False]['PATIENT_ID'])
    all_enrolled = responders | non_responders

    # Get features for enrolled patients
    spine = session.sql(f"""
        SELECT DISTINCT PATIENT_ID
        FROM PATIENT_TARGETING_DEMO.RAW.PROGRAM_OUTCOMES
        WHERE PROGRAM_NAME = '{program_name}'
    """)

    feature_views = fs.list_feature_views().to_pandas()
    fvs = [fs.get_feature_view(row.NAME, row.VERSION) for _, row in feature_views.iterrows()]
    features_df = fs.generate_training_set(
        spine_df=spine, features=fvs, spine_label_cols=[]
    ).to_pandas()

    features_df['IS_RESPONDER'] = features_df['PATIENT_ID'].isin(responders).astype(int)
    numeric_cols = features_df.select_dtypes(include=[np.number]).columns.tolist()
    numeric_cols = [c for c in numeric_cols if c != 'IS_RESPONDER']

    over_indexes = []
    under_indexes = []
    for col in numeric_cols:
        resp_mean = features_df[features_df['IS_RESPONDER'] == 1][col].mean()
        all_mean = features_df[col].mean()
        if all_mean != 0:
            ratio = resp_mean / all_mean
            entry = {"feature": col, "responder_mean": round(float(resp_mean), 3),
                     "overall_mean": round(float(all_mean), 3), "ratio": round(float(ratio), 3)}
            if ratio > 1.15:
                over_indexes.append(entry)
            elif ratio < 0.85:
                under_indexes.append(entry)

    return {
        "program_name": program_name,
        "total_enrolled": len(all_enrolled),
        "responders": len(responders),
        "non_responders": len(non_responders),
        "response_rate": round(len(responders) / len(all_enrolled) * 100, 1),
        "over_indexes": sorted(over_indexes, key=lambda x: x['ratio'], reverse=True),
        "under_indexes": sorted(under_indexes, key=lambda x: x['ratio'])
    }
$$;

-- Tool 4: Train XGBoost, score universe, compute lift, register model
CREATE OR REPLACE PROCEDURE PATIENT_TARGETING_DEMO.MODELS.TRAIN_AND_SCORE_PROGRAM(
    program_name VARCHAR, feature_list VARCHAR, model_name VARCHAR
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'snowflake-ml-python', 'xgboost', 'numpy', 'pandas', 'scikit-learn')
HANDLER = 'run'
AS
$$
import json as _json
import numpy as np
import pandas as pd
from snowflake.ml.feature_store import FeatureStore

def run(session, program_name, feature_list, model_name):
    feature_list = _json.loads(feature_list) if isinstance(feature_list, str) else list(feature_list)
    import xgboost as xgb
    from sklearn.metrics import roc_auc_score
    from sklearn.model_selection import train_test_split

    fs = FeatureStore(session=session, database="PATIENT_TARGETING_DEMO", name="FEATURE_STORE",
                      default_warehouse="PATIENT_TARGETING_WH")

    # Build labeled spine from program outcomes
    spine = session.sql(f"""
        SELECT PATIENT_ID, CASE WHEN GOT_FILL THEN 1 ELSE 0 END AS LABEL
        FROM PATIENT_TARGETING_DEMO.RAW.PROGRAM_OUTCOMES
        WHERE PROGRAM_NAME = '{program_name}'
    """)

    fv_list = fs.list_feature_views().to_pandas()
    fvs = [fs.get_feature_view(r.NAME, r.VERSION) for _, r in fv_list.iterrows()]

    train_df = fs.generate_training_set(
        spine_df=spine, features=fvs, spine_label_cols=['LABEL']
    ).to_pandas()

    available = [f for f in feature_list if f in train_df.columns]
    X = train_df[available].fillna(0)
    y = train_df['LABEL']

    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42, stratify=y)

    model = xgb.XGBClassifier(
        n_estimators=200, max_depth=5, learning_rate=0.1,
        subsample=0.8, colsample_bytree=0.8,
        eval_metric='auc', random_state=42, use_label_encoder=False
    )
    model.fit(X_train, y_train, eval_set=[(X_test, y_test)], verbose=False)

    y_pred_proba = model.predict_proba(X_test)[:, 1]
    auc = float(roc_auc_score(y_test, y_pred_proba))
    importance = dict(zip(available, [float(x) for x in model.feature_importances_]))

    # Score full universe
    universe_spine = session.sql("SELECT PATIENT_ID FROM PATIENT_TARGETING_DEMO.RAW.PATIENT_UNIVERSE")
    universe_df = fs.generate_training_set(
        spine_df=universe_spine, features=fvs, spine_label_cols=[]
    ).to_pandas()
    X_univ = universe_df[available].fillna(0)
    universe_df['SCORE'] = model.predict_proba(X_univ)[:, 1]
    universe_df['DECILE'] = pd.qcut(universe_df['SCORE'], 10, labels=False, duplicates='drop') + 1

    # Save scored output
    tag = model_name.upper().replace(' ', '_')
    session.create_dataframe(universe_df[['PATIENT_ID', 'SCORE', 'DECILE']]).write.mode('overwrite').save_as_table(
        f'PATIENT_TARGETING_DEMO.SCORING.{tag}_SCORED'
    )
    top_1000 = universe_df.nlargest(1000, 'SCORE')[['PATIENT_ID', 'SCORE', 'DECILE']]
    session.create_dataframe(top_1000).write.mode('overwrite').save_as_table(
        f'PATIENT_TARGETING_DEMO.SCORING.{tag}_TOP_1000'
    )

    # Lift by decile
    outcomes_pdf = session.sql(f"""
        SELECT PATIENT_ID, CASE WHEN GOT_FILL THEN 1 ELSE 0 END AS ACTUAL_RESPONSE
        FROM PATIENT_TARGETING_DEMO.RAW.PROGRAM_OUTCOMES
        WHERE PROGRAM_NAME = '{program_name}'
    """).to_pandas()
    eval_df = universe_df[['PATIENT_ID', 'SCORE', 'DECILE']].merge(outcomes_pdf, on='PATIENT_ID', how='left')
    eval_df['ACTUAL_RESPONSE'] = eval_df['ACTUAL_RESPONSE'].fillna(0)

    lift_records = []
    total_resp = eval_df['ACTUAL_RESPONSE'].sum()
    for decile in sorted(eval_df['DECILE'].unique()):
        d = eval_df[eval_df['DECILE'] == decile]
        resp = int(d['ACTUAL_RESPONSE'].sum())
        lift = round(float(resp / (total_resp / 10)), 2) if total_resp > 0 else 0.0
        lift_records.append({'DECILE': int(decile), 'TOTAL_PATIENTS': len(d), 'RESPONDERS': resp, 'LIFT': lift})

    session.create_dataframe(pd.DataFrame(lift_records)).write.mode('overwrite').save_as_table(
        f'PATIENT_TARGETING_DEMO.MONITORING.{tag}_LIFT'
    )

    # Register model
    from snowflake.ml.registry import Registry
    registry = Registry(session=session)
    registry.log_model(
        model=model,
        model_name=f'{tag}_TARGETING_MODEL',
        metrics={'auc': auc, 'n_features': len(available)},
        comment=f'Agent-created model for {program_name}. AUC: {auc:.4f}',
        sample_input_data=X_test.head(5)
    )

    sorted_imp = sorted(importance.items(), key=lambda x: x[1], reverse=True)
    confidence = "High" if auc > 0.75 else ("Medium" if auc > 0.65 else "Low")

    return {
        "model_name": tag,
        "program_name": program_name,
        "auc": round(auc, 4),
        "confidence": confidence,
        "top_features": [{"feature": k, "importance": round(v, 4)} for k, v in sorted_imp[:5]],
        "features_used": available,
        "training_size": len(train_df),
        "universe_scored": len(universe_df),
        "lift_decile_1": lift_records[0]['LIFT'] if lift_records else 0,
        "top_1000_min_score": round(float(top_1000['SCORE'].min()), 4)
    }
$$;


-- ─── 6. Verification Queries ────────────────────────────────────────────────

SELECT 'Patient Universe' AS check_name, COUNT(*) AS row_count FROM PATIENT_UNIVERSE;
SELECT 'Prescription History' AS check_name, COUNT(*) AS row_count FROM PRESCRIPTION_HISTORY;
SELECT 'Adherence Programs' AS check_name, COUNT(*) AS row_count FROM ADHERENCE_PROGRAMS;
SELECT 'Program Outcomes' AS check_name, COUNT(*) AS row_count FROM PROGRAM_OUTCOMES;

SELECT 'Patients by Payer Type' AS check_name;
SELECT payer_type, COUNT(*) AS patients,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct
FROM PATIENT_UNIVERSE
GROUP BY payer_type
ORDER BY patients DESC;

SELECT 'Programs by Type' AS check_name;
SELECT program_type, COUNT(*) AS programs
FROM ADHERENCE_PROGRAMS
GROUP BY program_type;

SELECT 'Outcome Rates by Program Type' AS check_name;
SELECT program_type,
       COUNT(*) AS total_enrolled,
       SUM(CASE WHEN got_fill THEN 1 ELSE 0 END) AS responded,
       ROUND(SUM(CASE WHEN got_fill THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS response_rate_pct
FROM PROGRAM_OUTCOMES
GROUP BY program_type
ORDER BY program_type;

SELECT 'Top 5 Programs by Enrollment' AS check_name;
SELECT program_name, program_type, COUNT(*) AS enrolled,
       ROUND(SUM(CASE WHEN got_fill THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS response_rate_pct
FROM PROGRAM_OUTCOMES
GROUP BY program_name, program_type
ORDER BY enrolled DESC
LIMIT 5;

SELECT 'Enrollment per Program' AS check_name;
SELECT program_name, program_type, target_gpi_class,
       COUNT(*) AS enrolled,
       ROUND(SUM(CASE WHEN got_fill THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS response_rate_pct
FROM PROGRAM_OUTCOMES
GROUP BY program_name, program_type, target_gpi_class
ORDER BY program_name;

-- Show all created objects
SHOW SCHEMAS IN DATABASE PATIENT_TARGETING_DEMO;
SHOW TABLES IN SCHEMA PATIENT_TARGETING_DEMO.RAW;
SHOW STAGES IN SCHEMA PATIENT_TARGETING_DEMO.MODELS;
