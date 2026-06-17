"""Cortex Agent ML Monitor: automated drift analysis, root cause explanation, and recommendations."""
from snowflake.snowpark import Session
import snowflake.snowpark.functions as F
from datetime import datetime
import json
import numpy as np
from utils import create_session, get_feature_config, get_fully_qualified_name, get_telemetry_config


feature_cfg = get_feature_config()
telemetry_cfg = get_telemetry_config()

GRAIN = feature_cfg["partition_col"]
TARGET = feature_cfg["target_col"]
TIME = feature_cfg["time_col"]


def create_insights_table(session: Session):
    """Create AGENT_INSIGHTS table if not exists."""
    fqn = get_fully_qualified_name("AGENT_INSIGHTS")
    session.sql(f"""
        CREATE TABLE IF NOT EXISTS {fqn} (
            INSIGHT_ID VARCHAR,
            CREATED_AT TIMESTAMP_NTZ,
            CATEGORY VARCHAR,
            STORE_ITEM_ID VARCHAR,
            SUMMARY VARCHAR,
            DETAIL VARCHAR(4000),
            RECOMMENDATION VARCHAR(2000),
            STATUS VARCHAR DEFAULT 'new',
            METADATA VARIANT
        )
    """).collect()
    print("   AGENT_INSIGHTS table ready")


def generate_insight_with_llm(session: Session, partition_id: str, 
                               current_mape: float, historical_mape: float,
                               feature_shifts: dict, context: str = "") -> dict:
    """
    Use Snowflake Cortex COMPLETE to generate natural language insight.
    Falls back to template-based insight if Cortex unavailable.
    """
    store_id = partition_id.split("_")[0] if "_" in partition_id else "Unknown"
    item_name = partition_id.split("_", 1)[1] if "_" in partition_id else partition_id

    prompt = f"""You are an ML operations analyst for retail store demand forecasting.
A forecasting model for store "{store_id}", item "{item_name}" has degraded.

Current 7-day MAPE: {current_mape:.1%}
Historical average MAPE: {historical_mape:.1%}
Degradation: {(current_mape - historical_mape)/max(historical_mape, 0.01):.0%} worse than baseline

Feature distribution changes detected in recent data:
{json.dumps(feature_shifts, indent=2) if feature_shifts else "No clear single-feature shift detected."}

{f"Additional context: {context}" if context else ""}

Provide a JSON response with exactly these keys:
- "summary": 1 sentence specific to this store/item combination. Reference the store ID and item name.
- "detail": 2-3 sentences. Include specific numbers (MAPE values, feature shifts). Explain the likely business reason.
- "recommendation": One specific, actionable next step. Be creative and varied — do NOT just say "retrain". Consider: feature engineering, store-level investigation, seasonal adjustments, data quality checks, or promotional effects. Tailor to the item type.

Important: Make each recommendation UNIQUE and SPECIFIC to this item and store. Avoid generic advice.

Respond ONLY with valid JSON, no markdown."""

    try:
        result = session.sql(f"""
            SELECT SNOWFLAKE.CORTEX.COMPLETE('mistral-large2', $${prompt}$$) AS RESPONSE
        """).collect()
        
        response_text = result[0]["RESPONSE"]
        clean = response_text.strip()
        if clean.startswith("```"):
            clean = clean.split("\n", 1)[1].rsplit("```", 1)[0].strip()
        insight = json.loads(clean)
        return insight
    except Exception as e:
        return {
            "summary": f"{store_id} {item_name}: MAPE degraded from {historical_mape:.0%} to {current_mape:.0%}. Feature analysis suggests external demand shift.",
            "detail": f"The model for {partition_id} has been consistently over/under-predicting for the past {telemetry_cfg['rolling_window_days']} days. Feature distribution analysis shows changes in: {', '.join(feature_shifts.keys()) if feature_shifts else 'no clear single factor'}.",
            "recommendation": f"Retrain model for {partition_id} with recent data. Consider investigating local factors affecting this store.",
        }


def analyze_drift_causes(session: Session, drifting_partitions: list) -> list:
    """Analyze WHY partitions are drifting by checking feature distribution shifts."""
    feature_fqn = get_fully_qualified_name("FEATURE_TABLE")
    telemetry_fqn = get_fully_qualified_name("FORECAST_TELEMETRY")
    
    analyses = []
    
    for partition_id in drifting_partitions[:10]:  # Limit to top 10 for performance
        # Check if features shifted
        try:
            recent_features = session.sql(f"""
                SELECT AVG(WEATHER_TEMP) AS AVG_TEMP,
                       AVG(IS_HOLIDAY) AS HOLIDAY_RATE,
                       AVG(SCHOOL_IN_SESSION) AS SCHOOL_RATE,
                       AVG(EVENT_FLAG) AS EVENT_RATE
                FROM {feature_fqn}
                WHERE {GRAIN} = '{partition_id}'
                  AND {TIME} >= DATEADD(day, -7, (SELECT MAX({TIME}) FROM {feature_fqn}))
            """).collect()
            
            historical_features = session.sql(f"""
                SELECT AVG(WEATHER_TEMP) AS AVG_TEMP,
                       AVG(IS_HOLIDAY) AS HOLIDAY_RATE,
                       AVG(SCHOOL_IN_SESSION) AS SCHOOL_RATE,
                       AVG(EVENT_FLAG) AS EVENT_RATE
                FROM {feature_fqn}
                WHERE {GRAIN} = '{partition_id}'
                  AND {TIME} < DATEADD(day, -7, (SELECT MAX({TIME}) FROM {feature_fqn}))
            """).collect()
            
            feature_shifts = {}
            if recent_features and historical_features:
                r = recent_features[0]
                h = historical_features[0]
                if r["SCHOOL_RATE"] is not None and h["SCHOOL_RATE"] is not None:
                    if abs(float(r["SCHOOL_RATE"]) - float(h["SCHOOL_RATE"])) > 0.3:
                        feature_shifts["SCHOOL_IN_SESSION"] = f"changed from {float(h['SCHOOL_RATE']):.1%} to {float(r['SCHOOL_RATE']):.1%}"
                if r["AVG_TEMP"] is not None and h["AVG_TEMP"] is not None:
                    if abs(float(r["AVG_TEMP"]) - float(h["AVG_TEMP"])) > 15:
                        feature_shifts["WEATHER_TEMP"] = f"shifted from {float(h['AVG_TEMP']):.0f}F to {float(r['AVG_TEMP']):.0f}F"
                if r["EVENT_RATE"] is not None and h["EVENT_RATE"] is not None:
                    if float(r["EVENT_RATE"]) > float(h["EVENT_RATE"]) + 0.1:
                        feature_shifts["EVENT_FLAG"] = f"event activity increased"
        except Exception:
            feature_shifts = {}
        
        analyses.append({
            "partition_id": partition_id,
            "feature_shifts": feature_shifts,
        })
    
    return analyses


def detect_opportunities(session: Session) -> list:
    """Look for improvement opportunities beyond drift."""
    telemetry_fqn = get_fully_qualified_name("FORECAST_TELEMETRY")
    
    opportunities = []
    
    # Find consistently over-predicting partitions (waste)
    over_pred = session.sql(f"""
        SELECT {GRAIN}, AVG(ERROR) AS AVG_BIAS, COUNT(*) AS N
        FROM {telemetry_fqn}
        WHERE ERROR > 0
        GROUP BY {GRAIN}
        HAVING AVG(ERROR) > 3 AND COUNT(*) > 100
        ORDER BY AVG_BIAS DESC
        LIMIT 5
    """).collect()
    
    for row in over_pred:
        opportunities.append({
            "category": "waste_reduction",
            "partition_id": row[GRAIN],
            "detail": f"Consistently over-predicting by {float(row['AVG_BIAS']):.1f} units/hour. Potential waste reduction opportunity.",
        })
    
    # Find consistently under-predicting (lost sales)
    under_pred = session.sql(f"""
        SELECT {GRAIN}, AVG(ERROR) AS AVG_BIAS, COUNT(*) AS N
        FROM {telemetry_fqn}
        WHERE ERROR < 0
        GROUP BY {GRAIN}
        HAVING AVG(ERROR) < -3 AND COUNT(*) > 100
        ORDER BY AVG_BIAS ASC
        LIMIT 5
    """).collect()
    
    for row in under_pred:
        opportunities.append({
            "category": "lost_sales",
            "partition_id": row[GRAIN],
            "detail": f"Consistently under-predicting by {abs(float(row['AVG_BIAS'])):.1f} units/hour. Potential lost revenue.",
        })
    
    return opportunities


def run_monitoring_cycle(session: Session = None, write_insights: bool = True):
    """Full monitoring cycle: detect drift, analyze causes, generate insights."""
    if session is None:
        session = create_session("agent_monitor")
        print(f"Connected: {session.get_current_account()}")
    
    print("=" * 60)
    print("CORTEX AGENT: ML MONITORING CYCLE")
    print("=" * 60)
    
    create_insights_table(session)
    telemetry_fqn = get_fully_qualified_name("FORECAST_TELEMETRY")
    insights_fqn = get_fully_qualified_name("AGENT_INSIGHTS")
    
    # Get drifting partitions
    drifting = session.sql(f"""
        SELECT {GRAIN}, MAX(ROLLING_7D_MAPE) AS CURRENT_MAPE
        FROM {telemetry_fqn}
        WHERE DRIFT_FLAG = TRUE
        GROUP BY {GRAIN}
        ORDER BY CURRENT_MAPE DESC
        LIMIT {telemetry_cfg.get('alert_top_n', 20)}
    """).collect()
    
    if not drifting:
        print("   No drifting partitions detected. All models performing within threshold.")
        return []
    
    print(f"\n   Found {len(drifting)} drifting partitions. Analyzing root causes...")
    
    drifting_ids = [row[GRAIN] for row in drifting]
    analyses = analyze_drift_causes(session, drifting_ids)
    
    # Generate insights
    all_insights = []
    for i, (drift_row, analysis) in enumerate(zip(drifting, analyses)):
        partition_id = drift_row[GRAIN]
        current_mape = float(drift_row["CURRENT_MAPE"])
        
        insight = generate_insight_with_llm(
            session, partition_id,
            current_mape=current_mape,
            historical_mape=0.10,  # baseline assumption
            feature_shifts=analysis["feature_shifts"],
        )
        
        insight_record = {
            "partition_id": partition_id,
            "category": "drift",
            "current_mape": current_mape,
            **insight,
        }
        all_insights.append(insight_record)
        
        if write_insights:
            session.sql(f"""
                INSERT INTO {insights_fqn} 
                (INSIGHT_ID, CREATED_AT, CATEGORY, STORE_ITEM_ID, SUMMARY, DETAIL, RECOMMENDATION, STATUS)
                SELECT UUID_STRING(), CURRENT_TIMESTAMP(), 'drift', '{partition_id}',
                       '{insight["summary"].replace("'", "''")}',
                       '{insight["detail"].replace("'", "''")}',
                       '{insight["recommendation"].replace("'", "''")}',
                       'new'
            """).collect()
    
    # Check for opportunities
    opportunities = detect_opportunities(session)
    for opp in opportunities:
        all_insights.append(opp)
        if write_insights:
            session.sql(f"""
                INSERT INTO {insights_fqn}
                (INSIGHT_ID, CREATED_AT, CATEGORY, STORE_ITEM_ID, SUMMARY, DETAIL, RECOMMENDATION, STATUS)
                SELECT UUID_STRING(), CURRENT_TIMESTAMP(), '{opp["category"]}', '{opp["partition_id"]}',
                       '{opp["detail"][:200].replace("'", "''")}',
                       '{opp["detail"].replace("'", "''")}',
                       'Review production levels for this store-item combination.',
                       'new'
            """).collect()
    
    print(f"\n   Generated {len(all_insights)} insights")
    print(f"   Written to AGENT_INSIGHTS table")
    
    return all_insights



def get_recent_insights(session: Session, limit: int = 20) -> list:
    """Return recent insights for Streamlit display."""
    insights_fqn = get_fully_qualified_name("AGENT_INSIGHTS")
    
    rows = session.sql(f"""
        SELECT * FROM {insights_fqn}
        ORDER BY CREATED_AT DESC
        LIMIT {limit}
    """).collect()
    
    return [dict(row) for row in rows]


if __name__ == "__main__":
    session = create_session()
    print(f"Connected: {session.get_current_account()}")
    run_monitoring_cycle(session)
