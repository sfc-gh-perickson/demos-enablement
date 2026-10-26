"""
Graph Fraud Detection — Training Script

Runs as an ML Job on SPCS via submit_directory(), or locally / in Container Runtime.
Loads FRAUD_TRAINING_DATA (generated from Feature Store point-in-time joins),
trains XGBoost on 15 graph-community features, logs to ExperimentTracking,
optionally registers to Model Registry.

Environment variables (injected by ML Job / Tuner):
    DATABASE          GRAPH_FRAUD_DEMO
    SCHEMA            MODELS
    EXPERIMENT_NAME   GRAPH_FRAUD_EXPERIMENT
    VERSION_NAME      (optional) if set + REGISTER_MODEL=true, registers the model
    REGISTER_MODEL    true | false
    N_ESTIMATORS      200
    MAX_DEPTH         5
    LEARNING_RATE     0.05
    SUBSAMPLE         0.8
    COLSAMPLE_BYTREE  0.8
    MIN_CHILD_WEIGHT  1
"""

import os
import pickle
import time

import pandas as pd
import xgboost as xgb
from sklearn.model_selection import train_test_split
from sklearn.metrics import (
    accuracy_score, precision_score, recall_score, f1_score,
    roc_auc_score, average_precision_score, confusion_matrix,
    classification_report,
)
from snowflake.snowpark import Session
from snowflake.ml.experiment import ExperimentTracking

DATABASE         = os.environ.get('DATABASE',         'GRAPH_FRAUD_DEMO')
SCHEMA           = os.environ.get('SCHEMA',           'MODELS')
EXPERIMENT_NAME  = os.environ.get('EXPERIMENT_NAME',  'GRAPH_FRAUD_EXPERIMENT')
VERSION_NAME     = os.environ.get('VERSION_NAME',     None)
REGISTER_MODEL   = os.environ.get('REGISTER_MODEL',   'false').lower() == 'true'
MODEL_STAGE      = os.environ.get('MODEL_STAGE',      f'@{DATABASE}.{SCHEMA}.ML_MODELS')

N_ESTIMATORS     = int(os.environ.get('N_ESTIMATORS',    '200'))
MAX_DEPTH        = int(os.environ.get('MAX_DEPTH',        '5'))
LEARNING_RATE    = float(os.environ.get('LEARNING_RATE',  '0.05'))
SUBSAMPLE        = float(os.environ.get('SUBSAMPLE',      '0.8'))
COLSAMPLE_BYTREE = float(os.environ.get('COLSAMPLE_BYTREE', '0.8'))
MIN_CHILD_WEIGHT = float(os.environ.get('MIN_CHILD_WEIGHT', '1'))
GAMMA            = float(os.environ.get('GAMMA',            '0'))
REG_ALPHA        = float(os.environ.get('REG_ALPHA',        '0'))
REG_LAMBDA       = float(os.environ.get('REG_LAMBDA',       '1'))

FEATURE_COLS = [
    'EFFECTIVE_COMMUNITY_SIZE',
    'DEGREE',
    'SHARED_ADDRESS_COUNT',
    'SHARED_IP_COUNT',
    'AVG_COMMUNITY_REFUND',
    'COMMUNITY_REFUND_STDDEV',
    'ADDR_N_FILERS',
    'ADDR_AVG_REFUND',
    'IP_N_FILERS',
    'IP_AVG_REFUND',
    'SUBMISSION_HOUR',
    'IS_HIGH_CLAIM',
    'IS_ODD_HOUR',
    'CLAIM_AMOUNT',
    'HAS_DIRECT_GRAPH',
]
LABEL_COL = 'IS_FRAUD'
MODEL_FILE   = 'fraud_ring_model.pkl'
METRICS_FILE = 'fraud_ring_metrics.pkl'


def calculate_metrics(y_true, y_pred, y_proba):
    cm = confusion_matrix(y_true, y_pred)
    tn, fp, fn, tp = cm.ravel()
    return {
        'accuracy':           float(accuracy_score(y_true, y_pred)),
        'precision':          float(precision_score(y_true, y_pred, zero_division=0)),
        'recall':             float(recall_score(y_true, y_pred, zero_division=0)),
        'f1':                 float(f1_score(y_true, y_pred, zero_division=0)),
        'auc_roc':            float(roc_auc_score(y_true, y_proba)),
        'auc_pr':             float(average_precision_score(y_true, y_proba)),
        'true_positives':     int(tp),
        'false_positives':    int(fp),
        'true_negatives':     int(tn),
        'false_negatives':    int(fn),
        'fraud_detection_rate': float(recall_score(y_true, y_pred, zero_division=0)),
        'false_positive_rate':  float(fp / (fp + tn)) if (fp + tn) > 0 else 0.0,
    }


def main():
    print('=== Graph Fraud Detection Training ===')

    session = Session.builder.getOrCreate()
    print('Connected to Snowflake')

    exp = ExperimentTracking(session=session, database_name=DATABASE, schema_name=SCHEMA)
    exp.set_experiment(EXPERIMENT_NAME)
    print(f'Experiment: {EXPERIMENT_NAME}')

    print(f'Loading training data via Feature Store generate_training_set...')
    from snowflake.ml.feature_store import FeatureStore, CreationMode

    session.use_database(DATABASE)

    fs = FeatureStore(
        session=session,
        database=DATABASE,
        name='FEATURES',
        default_warehouse='GRAPH_FRAUD_WH',
        creation_mode=CreationMode.FAIL_IF_NOT_EXIST,
    )

    graph_fv = fs.get_feature_view('GRAPH_COMMUNITY_FEATURES', 'V1')

    # Also get address + IP FVs for training (these provide heuristic features)
    try:
        addr_fv = fs.get_feature_view('ADDRESS_COMMUNITY_FEATURES', 'V1')
        ip_fv = fs.get_feature_view('IP_COMMUNITY_FEATURES', 'V1')
        extra_fvs = [addr_fv, ip_fv]
        print('  Including ADDRESS + IP FVs in training set')
    except Exception:
        extra_fvs = []
        print('  ADDRESS/IP FVs not found — training on graph FV only')

    # Spine: applicants with fraud labels + derived features from APPLICATIONS
    # Includes the 6 features that the real-time FV computes at inference time
    spine_df = session.sql(f"""
        SELECT
            cr.APPLICANT_ID::VARCHAR AS APPLICANT_ID,
            tr.ADDRESS_ID::VARCHAR AS ADDRESS_ID,
            tr.IP_ADDRESS::VARCHAR AS IP_ADDRESS,
            tr.SUBMITTED_AT,
            tr.CLAIM_AMOUNT::DOUBLE AS CLAIM_AMOUNT,
            HOUR(tr.SUBMITTED_AT)::DOUBLE AS SUBMISSION_HOUR,
            CASE WHEN tr.CLAIM_AMOUNT > 10000 THEN 1.0 ELSE 0.0 END AS IS_HIGH_CLAIM,
            CASE WHEN HOUR(tr.SUBMITTED_AT) BETWEEN 0 AND 5 THEN 1.0 ELSE 0.0 END AS IS_ODD_HOUR,
            CASE WHEN cr.COMMUNITY_SIZE > 0 THEN cr.COMMUNITY_SIZE ELSE 0.0 END::DOUBLE AS EFFECTIVE_COMMUNITY_SIZE,
            CASE WHEN cr.COMMUNITY_SIZE > 0 THEN 1.0 ELSE 0.0 END AS HAS_DIRECT_GRAPH,
            CASE WHEN frm.APPLICANT_ID IS NOT NULL THEN 1.0 ELSE 0.0 END AS IS_FRAUD
        FROM {DATABASE}.GRAPH.COMMUNITY_RESULTS cr
        JOIN {DATABASE}.RAW.APPLICATIONS tr ON tr.APPLICANT_ID = cr.APPLICANT_ID
        LEFT JOIN {DATABASE}.RAW.FRAUD_RING_MEMBERS frm ON frm.APPLICANT_ID = cr.APPLICANT_ID
        QUALIFY ROW_NUMBER() OVER (PARTITION BY cr.APPLICANT_ID ORDER BY tr.SUBMITTED_AT DESC) = 1
    """)

    training_sdf = fs.generate_training_set(
        spine_df=spine_df,
        features=[graph_fv] + extra_fvs,
        spine_timestamp_col='SUBMITTED_AT',
        spine_label_cols=['IS_FRAUD'],
    )

    train_pdf = training_sdf.to_pandas()
    print(f'  Loaded {len(train_pdf):,} rows, {len(train_pdf.columns)} columns')

    available = [c for c in FEATURE_COLS if c in train_pdf.columns]
    missing   = [c for c in FEATURE_COLS if c not in train_pdf.columns]
    if missing:
        print(f'  WARNING: {len(missing)} feature cols not found: {missing[:5]}...')
    print(f'  Using {len(available)} features')

    X = train_pdf[available].fillna(0)
    y = train_pdf[LABEL_COL].fillna(0)

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )
    print(f'  Train: {len(X_train):,} | Test: {len(X_test):,}')
    print(f'  Fraud rate — Train: {y_train.mean()*100:.2f}% | Test: {y_test.mean()*100:.2f}%')

    neg = int((y_train == 0).sum())
    pos = int((y_train == 1).sum())
    scale_pos_weight = neg / max(pos, 1)
    print(f'  scale_pos_weight: {scale_pos_weight:.2f}')

    params = {
        'n_estimators':    N_ESTIMATORS,
        'max_depth':       MAX_DEPTH,
        'learning_rate':   LEARNING_RATE,
        'scale_pos_weight': scale_pos_weight,
        'subsample':       SUBSAMPLE,
        'colsample_bytree': COLSAMPLE_BYTREE,
        'min_child_weight': MIN_CHILD_WEIGHT,
        'gamma':           GAMMA,
        'reg_alpha':       REG_ALPHA,
        'reg_lambda':      REG_LAMBDA,
        'random_state':    42,
        'eval_metric':     'logloss',
    }
    print(f'\nTraining XGBoost... {params}')
    model = xgb.XGBClassifier(**params)
    model.fit(X_train, y_train)
    print('Training complete')

    y_proba = model.predict_proba(X_test)[:, 1]

    # Threshold optimization: sweep to maximize F1
    import numpy as np
    thresholds = np.arange(0.05, 0.95, 0.01)
    f1_scores = [f1_score(y_test, (y_proba >= t).astype(int), zero_division=0) for t in thresholds]
    best_threshold = float(thresholds[np.argmax(f1_scores)])
    print(f'  Optimal threshold: {best_threshold:.2f} (F1: {max(f1_scores):.4f})')

    y_pred = (y_proba >= best_threshold).astype(int)
    print(classification_report(y_test, y_pred, target_names=['Legitimate', 'Fraud']))

    metrics = calculate_metrics(y_test.values, y_pred, y_proba)
    metrics['threshold'] = best_threshold
    for k, v in metrics.items():
        print(f'  {k}: {v:.4f}' if isinstance(v, float) else f'  {k}: {v}')

    run_name = f'xgb_graph_fraud_{int(time.time())}'
    with exp.start_run(run_name):
        exp.log_params({
            'n_estimators':    str(N_ESTIMATORS),
            'max_depth':       str(MAX_DEPTH),
            'learning_rate':   str(LEARNING_RATE),
            'scale_pos_weight': str(round(scale_pos_weight, 2)),
            'subsample':       str(SUBSAMPLE),
            'colsample_bytree': str(COLSAMPLE_BYTREE),
            'run_type':        'graph_fraud_ml_job',
        })
        exp.log_metrics({
            'test_auc_roc':  metrics['auc_roc'],
            'test_auc_pr':   metrics['auc_pr'],
            'test_recall':   metrics['recall'],
            'test_precision': metrics['precision'],
            'test_f1':       metrics['f1'],
        })
    print(f'Logged run: {run_name}')

    os.makedirs('/tmp/model', exist_ok=True)
    model_path   = f'/tmp/model/{MODEL_FILE}'
    metrics_path = f'/tmp/model/{METRICS_FILE}'

    with open(model_path, 'wb') as f:
        pickle.dump({'model': model, 'features': available}, f)
    with open(metrics_path, 'wb') as f:
        pickle.dump(metrics, f)

    session.sql(f'CREATE STAGE IF NOT EXISTS {DATABASE}.{SCHEMA}.ML_MODELS').collect()
    session.file.put(model_path,   MODEL_STAGE, auto_compress=False, overwrite=True)
    session.file.put(metrics_path, MODEL_STAGE, auto_compress=False, overwrite=True)
    print(f'Artifacts uploaded to {MODEL_STAGE}')

    test_df = pd.concat([X_test.reset_index(drop=True), y_test.reset_index(drop=True)], axis=1)
    session.create_dataframe(test_df).write.mode('overwrite').save_as_table(
        f'{DATABASE}.{SCHEMA}.FRAUD_TEST_DATA'
    )

    if REGISTER_MODEL and VERSION_NAME:
        from snowflake.ml.registry import Registry
        from snowflake.ml.model import type_hints
        print(f'\nRegistering model as FRAUD_RING_MODEL:{VERSION_NAME}...')
        reg = Registry(session=session, database_name=DATABASE, schema_name=SCHEMA)
        sample_df = session.create_dataframe(X_test.head(100))
        reg.log_model(
            model=model,
            model_name='FRAUD_RING_MODEL',
            version_name=VERSION_NAME,
            sample_input_data=sample_df,
            metrics={
                'auc':       metrics['auc_roc'],
                'recall':    metrics['recall'],
                'precision': metrics['precision'],
                'f1':        metrics['f1'],
            },
            comment=f'Graph fraud model — AUC: {metrics["auc_roc"]:.4f}',
            target_platforms=[type_hints.TargetPlatform.SNOWPARK_CONTAINER_SERVICES],
        )
        print(f'Registered: FRAUD_RING_MODEL:{VERSION_NAME}')

    print(f'\n=== Training Complete ===')
    print(f'AUC-ROC  : {metrics["auc_roc"]:.4f}')
    print(f'Recall   : {metrics["recall"]:.4f}')
    print(f'Precision: {metrics["precision"]:.4f}')


if __name__ == '__main__':
    main()
