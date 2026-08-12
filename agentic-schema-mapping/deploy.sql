-- =============================================================================
-- Schema Mapper Agent — Consolidated Deployment Script
-- =============================================================================
--
-- DEPLOYMENT INSTRUCTIONS:
--   1. Run this entire script in a Snowflake worksheet (or via SnowSQL/snow CLI)
--   2. Prerequisites:
--      - Database ACME_FINANCE and schema INGESTION must already exist (see setup.sql)
--      - Reference data must be seeded (see seed_reference_data.sql)
--      - Stage @UPLOAD_STAGE must exist (see setup.sql)
--      - Cortex AI models enabled (claude-4-sonnet)
--      - Cross-region inference enabled if models aren't in your region
--   3. This script is idempotent (all CREATE OR REPLACE) — safe to re-run
--
-- OBJECTS DEPLOYED:
--   - 2 File Formats (CSV_FF, CSV_FF_READ)
--   - 4 UDFs (LIST_STAGED_FILES, GET_TARGET_SCHEMAS, AI_PROPOSE_MAPPING, AI_RESOLVE_VALUES)
--   - 7 Stored Procedures:
--       Profiling:   SP_PROFILE_STAGED_FILE, PROFILE_FILE
--       Mapping:     PROPOSE_MAPPING
--       Resolution:  SP_RESOLVE_COLUMN_VALUES, PREVIEW_RESOLUTION
--       Execution:   SP_BUILD_AND_EXECUTE_COPY_INTO, EXECUTE_MAPPING
--   - 1 Cortex Agent (SCHEMA_MAPPER_AGENT)
--
-- =============================================================================

USE SCHEMA ACME_FINANCE.INGESTION;

-- =============================================================================
-- FILE FORMATS
-- =============================================================================

CREATE OR REPLACE FILE FORMAT CSV_FF
    PARSE_HEADER = TRUE
    TRIM_SPACE = TRUE
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
;

CREATE OR REPLACE FILE FORMAT CSV_FF_READ
    SKIP_HEADER = 1
    TRIM_SPACE = TRUE
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
;

-- =============================================================================
-- USER-DEFINED FUNCTIONS
-- =============================================================================

-- LIST_STAGED_FILES
-- Returns a newline-separated list of CSV filenames currently on the upload stage.
CREATE OR REPLACE FUNCTION LIST_STAGED_FILES()
RETURNS VARCHAR
LANGUAGE SQL
AS '
SELECT LISTAGG(RELATIVE_PATH, ''\n'') WITHIN GROUP (ORDER BY LAST_MODIFIED DESC)
FROM DIRECTORY(@ACME_FINANCE.INGESTION.UPLOAD_STAGE)
WHERE RELATIVE_PATH LIKE ''%.csv%''
';

-- GET_TARGET_SCHEMAS
-- Returns a formatted text block listing all canonical target tables and their columns.
CREATE OR REPLACE FUNCTION GET_TARGET_SCHEMAS()
RETURNS VARCHAR
LANGUAGE SQL
AS '
SELECT ''Available target tables and their columns:\n\n'' ||
''1. MILEAGE_CLAIMS:\n'' ||
''   Columns: '' || (SELECT LISTAGG(COLUMN_NAME, '', '') WITHIN GROUP (ORDER BY ORDINAL_POSITION) FROM ACME_FINANCE.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=''INGESTION'' AND TABLE_NAME=''MILEAGE_CLAIMS'') || ''\n\n'' ||
''2. PURCHASE_EXPENSES:\n'' ||
''   Columns: '' || (SELECT LISTAGG(COLUMN_NAME, '', '') WITHIN GROUP (ORDER BY ORDINAL_POSITION) FROM ACME_FINANCE.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=''INGESTION'' AND TABLE_NAME=''PURCHASE_EXPENSES'') || ''\n\n'' ||
''3. VENDOR_INVOICES:\n'' ||
''   Columns: '' || (SELECT LISTAGG(COLUMN_NAME, '', '') WITHIN GROUP (ORDER BY ORDINAL_POSITION) FROM ACME_FINANCE.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=''INGESTION'' AND TABLE_NAME=''VENDOR_INVOICES'')
';

-- AI_PROPOSE_MAPPING
-- The primary LLM call for column mapping. Uses claude-4-sonnet with structured output.
CREATE OR REPLACE FUNCTION AI_PROPOSE_MAPPING(PROMPT VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
AS '
SELECT AI_COMPLETE(
    model => ''claude-4-sonnet'',
    prompt => PROMPT,
    response_format => TYPE OBJECT(
        target_table VARCHAR,
        mappings ARRAY(OBJECT(source VARCHAR, dest VARCHAR, operation VARCHAR, ref_table VARCHAR)),
        ignored ARRAY(VARCHAR),
        unmapped_target_columns ARRAY(VARCHAR),
        rationale VARCHAR
    )
)
';

-- AI_RESOLVE_VALUES
-- Entity resolution LLM call. Uses claude-4-sonnet with structured output.
CREATE OR REPLACE FUNCTION AI_RESOLVE_VALUES(PROMPT VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
AS '
SELECT AI_COMPLETE(
    model => ''claude-4-sonnet'',
    prompt => PROMPT,
    response_format => TYPE OBJECT(
        mappings ARRAY(OBJECT(source_value VARCHAR, canonical_value VARCHAR))
    )
)
';


-- =============================================================================
-- STORED PROCEDURES — Profiling
-- =============================================================================

-- SP_PROFILE_STAGED_FILE
-- Core profiling engine. Analyzes a staged CSV without loading it.
CREATE OR REPLACE PROCEDURE SP_PROFILE_STAGED_FILE(STAGE_PATH VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
    clean_path     VARCHAR;
    full_stage_ref VARCHAR;
    result         VARIANT;
BEGIN
    clean_path := REPLACE(REPLACE(:STAGE_PATH, ''@UPLOAD_STAGE/'', ''''), ''@ACME_FINANCE.INGESTION.UPLOAD_STAGE/'', '''');
    full_stage_ref := ''@ACME_FINANCE.INGESTION.UPLOAD_STAGE/'' || :clean_path;

    -- Get column names ordered
    LET col_names_query VARCHAR := ''SELECT ARRAY_AGG(COLUMN_NAME) WITHIN GROUP (ORDER BY ORDER_ID) AS col_names FROM TABLE(INFER_SCHEMA(LOCATION => '''''' || :full_stage_ref || '''''', FILE_FORMAT => ''''ACME_FINANCE.INGESTION.CSV_FF''''))'';
    LET col_names VARIANT;
    LET rs3 RESULTSET := (EXECUTE IMMEDIATE :col_names_query);
    LET cur3 CURSOR FOR rs3;
    OPEN cur3;
    FETCH cur3 INTO col_names;
    CLOSE cur3;

    -- Get column types as object
    LET types_query VARCHAR := ''SELECT OBJECT_AGG(COLUMN_NAME, TYPE::VARIANT) AS col_types FROM TABLE(INFER_SCHEMA(LOCATION => '''''' || :full_stage_ref || '''''', FILE_FORMAT => ''''ACME_FINANCE.INGESTION.CSV_FF''''))'';
    LET col_types VARIANT;
    LET rs4 RESULTSET := (EXECUTE IMMEDIATE :types_query);
    LET cur4 CURSOR FOR rs4;
    OPEN cur4;
    FETCH cur4 INTO col_types;
    CLOSE cur4;

    -- Count total rows
    LET count_query VARCHAR := ''SELECT COUNT(*) FROM '' || :full_stage_ref || '' (FILE_FORMAT => ''''ACME_FINANCE.INGESTION.CSV_FF_READ'''')'';
    LET row_count NUMBER;
    LET rs5 RESULTSET := (EXECUTE IMMEDIATE :count_query);
    LET cur5 CURSOR FOR rs5;
    OPEN cur5;
    FETCH cur5 INTO row_count;
    CLOSE cur5;

    -- Build sample rows query
    LET num_cols NUMBER := ARRAY_SIZE(:col_names);
    LET sample_query VARCHAR := ''SELECT ARRAY_AGG(OBJECT_CONSTRUCT('';
    LET i NUMBER := 0;
    WHILE (i < :num_cols) DO
        IF (i > 0) THEN
            sample_query := :sample_query || '', '';
        END IF;
        sample_query := :sample_query || '''''''' || GET(:col_names, :i)::VARCHAR || '''''', $'' || (:i + 1)::VARCHAR || ''::VARCHAR'';
        i := :i + 1;
    END WHILE;
    sample_query := :sample_query || '')) FROM '' || :full_stage_ref || '' (FILE_FORMAT => ''''ACME_FINANCE.INGESTION.CSV_FF_READ'''') LIMIT 20'';
    
    LET sample_data VARIANT;
    LET rs6 RESULTSET := (EXECUTE IMMEDIATE :sample_query);
    LET cur6 CURSOR FOR rs6;
    OPEN cur6;
    FETCH cur6 INTO sample_data;
    CLOSE cur6;

    -- Build per-column summary from sample data
    LET columns_arr VARIANT := ARRAY_CONSTRUCT();
    i := 0;
    WHILE (i < :num_cols) DO
        LET col_name VARCHAR := GET(:col_names, :i)::VARCHAR;
        LET col_type VARCHAR := GET(:col_types, :col_name)::VARCHAR;
        
        LET vals VARIANT := ARRAY_CONSTRUCT();
        LET card NUMBER := 0;
        LET nulls NUMBER := 0;
        LET total NUMBER := ARRAY_SIZE(:sample_data);
        LET j NUMBER := 0;
        LET seen VARIANT := ARRAY_CONSTRUCT();
        
        WHILE (j < :total AND j < 20) DO
            LET val VARCHAR := GET(GET(:sample_data, :j), :col_name)::VARCHAR;
            IF (val IS NULL OR val = '''') THEN
                nulls := :nulls + 1;
            ELSE
                IF (NOT ARRAY_CONTAINS(val::VARIANT, :seen)) THEN
                    seen := ARRAY_APPEND(:seen, val::VARIANT);
                    IF (ARRAY_SIZE(:vals) < 5) THEN
                        vals := ARRAY_APPEND(:vals, val::VARIANT);
                    END IF;
                END IF;
            END IF;
            j := :j + 1;
        END WHILE;
        
        card := ARRAY_SIZE(:seen);
        
        LET col_obj VARIANT := OBJECT_CONSTRUCT(
            ''name'', :col_name,
            ''inferred_type'', :col_type,
            ''cardinality'', :card,
            ''null_rate'', ROUND(DIV0(:nulls, :total), 3),
            ''sample_values'', :vals
        );
        columns_arr := ARRAY_APPEND(:columns_arr, :col_obj);
        i := :i + 1;
    END WHILE;

    result := OBJECT_CONSTRUCT(
        ''columns'',        :columns_arr,
        ''column_names'',   :col_names,
        ''inferred_types'', :col_types,
        ''sample_values'',  :sample_data,
        ''patterns'',       ARRAY_CONSTRUCT(),
        ''row_count'',      :row_count,
        ''file_path'',      :STAGE_PATH
    );

    RETURN :result;
END;
';

-- PROFILE_FILE
-- Agent-facing wrapper around SP_PROFILE_STAGED_FILE.
CREATE OR REPLACE PROCEDURE PROFILE_FILE(FILE_PATH VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
    result VARCHAR;
BEGIN
    LET profile VARIANT;
    CALL ACME_FINANCE.INGESTION.SP_PROFILE_STAGED_FILE(:FILE_PATH) INTO :profile;
    
    LET col_text VARCHAR := '''';
    LET i NUMBER := 0;
    LET cols VARIANT := :profile:columns;
    LET num_cols NUMBER := ARRAY_SIZE(:cols);
    
    WHILE (i < :num_cols) DO
        LET c VARIANT := GET(:cols, :i);
        col_text := :col_text || ''  - '' || :c:name::VARCHAR || '' ('' || :c:inferred_type::VARCHAR || ''): '';
        col_text := :col_text || ''cardinality='' || :c:cardinality::VARCHAR || '', null_rate='' || :c:null_rate::VARCHAR;
        col_text := :col_text || '', samples='' || TO_JSON(:c:sample_values) || ''\n'';
        i := :i + 1;
    END WHILE;
    
    result := ''File: '' || :FILE_PATH || ''\n'' ||
              ''Row count: '' || :profile:row_count::VARCHAR || ''\n'' ||
              ''Column names (in order): '' || TO_JSON(:profile:column_names) || ''\n'' ||
              ''Columns:\n'' || :col_text;
    
    RETURN :result;
END;
';


-- =============================================================================
-- STORED PROCEDURES — Mapping Proposal
-- =============================================================================

-- PROPOSE_MAPPING
-- Agent-facing tool called in Step 3 of the workflow.
CREATE OR REPLACE PROCEDURE PROPOSE_MAPPING(PROFILE_TEXT VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    schemas VARCHAR;
    prompt VARCHAR;
    result VARIANT;
    clean_profile VARCHAR;
BEGIN
    clean_profile := REPLACE(REPLACE(REPLACE(:PROFILE_TEXT, '"', ''), CHR(10), ' '), '''', '');

    -- Check cache
    LET col_names_match VARCHAR := REGEXP_SUBSTR(:PROFILE_TEXT, 'Column names \(in order\): (\[.*?\])', 1, 1, 'e');
    IF (:col_names_match IS NOT NULL) THEN
        LET col_array VARIANT := TRY_PARSE_JSON(:col_names_match);
        IF (:col_array IS NOT NULL) THEN
            LET sorted_sig VARCHAR := (SELECT LISTAGG(LOWER(f.value::VARCHAR), '|') WITHIN GROUP (ORDER BY LOWER(f.value::VARCHAR)) FROM TABLE(FLATTEN(INPUT => :col_array)) f);
            LET col_hash VARCHAR := SHA2(:sorted_sig);
            LET cached_count NUMBER := (SELECT COUNT(*) FROM ACME_FINANCE.INGESTION.MAPPING_CONFIGS WHERE SOURCE_COLUMN_HASH = :col_hash);
            IF (:cached_count > 0) THEN
                LET cached_target VARCHAR;
                LET cached_map VARCHAR;
                LET cached_id VARCHAR;
                LET cached_times NUMBER;
                SELECT TARGET_TABLE, TO_JSON(COLUMN_MAP), CONFIG_ID, COALESCE(TIMES_USED, 0)
                INTO :cached_target, :cached_map, :cached_id, :cached_times
                FROM ACME_FINANCE.INGESTION.MAPPING_CONFIGS WHERE SOURCE_COLUMN_HASH = :col_hash
                ORDER BY CREATED_AT DESC LIMIT 1;
                UPDATE ACME_FINANCE.INGESTION.MAPPING_CONFIGS SET TIMES_USED = COALESCE(TIMES_USED, 0) + 1, LAST_USED_AT = CURRENT_TIMESTAMP() WHERE CONFIG_ID = :cached_id;
                RETURN '{"target_table": "' || :cached_target || '", "mappings": ' || :cached_map || ', "ignored": [], "unmapped_target_columns": [], "rationale": "(Cached, used ' || (:cached_times + 1)::VARCHAR || 'x. Zero tokens.)"}';
            END IF;
        END IF;
    END IF;

    -- Build prompt
    schemas := REPLACE(REPLACE((SELECT ACME_FINANCE.INGESTION.GET_TARGET_SCHEMAS()), CHR(10), ' '), '''', '');
    
    prompt := 'Map CSV columns to best canonical table. ' || :schemas || ' REF TABLES: REF_EXPENSE_CATEGORIES, REF_VENDORS, REF_GL_ACCOUNTS, REF_DEPARTMENTS, REF_COST_CENTERS, REF_PAYMENT_METHODS. CSV: ' || :clean_profile || ' OPS: TRIM, NUMERIC_STRIP_UNITS, TO_DATE, TO_DATE_START, TO_DATE_END, TO_NUMBER, DIRECT, RESOLVE_ENTITY (needs ref_table, use when source has descriptive text matching ref values). Source can map to multiple dests. Each dest once. Map as many as possible. IMPORTANT: In unmapped_target_columns, list ALL columns from the chosen target table that do NOT have a mapping from any source column. This tells the user what data will be missing.';

    BEGIN
        result := (SELECT ACME_FINANCE.INGESTION.AI_PROPOSE_MAPPING(:prompt));
    EXCEPTION
        WHEN OTHER THEN
            RETURN '{"error": "AI_PROPOSE_MAPPING failed: ' || REPLACE(REPLACE(SQLERRM, '"', ''), '''', '') || '"}';
    END;
    
    IF (:result IS NULL) THEN
        RETURN '{"error": "UDF returned NULL", "prompt_length": ' || LENGTH(:prompt)::VARCHAR || '}';
    END IF;
    
    RETURN TO_JSON(:result);
END;
$$;

-- =============================================================================
-- STORED PROCEDURES — Entity Resolution
-- =============================================================================

-- SP_RESOLVE_COLUMN_VALUES
-- Resolves descriptive text values to canonical reference values using LLM + caching.
CREATE OR REPLACE PROCEDURE SP_RESOLVE_COLUMN_VALUES(STAGE_PATH VARCHAR, COLUMN_POSITION NUMBER(38,0), REF_TABLE_NAME VARCHAR, TARGET_COLUMN VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS OWNER
AS '
DECLARE
    distinct_values VARIANT;
    ref_values VARIANT;
    resolution_map VARIANT;
    cache_hash VARCHAR;
BEGIN
    LET clean_path VARCHAR := REPLACE(REPLACE(:STAGE_PATH, ''@UPLOAD_STAGE/'', ''''), ''@ACME_FINANCE.INGESTION.UPLOAD_STAGE/'', '''');
    LET full_stage VARCHAR := ''@ACME_FINANCE.INGESTION.UPLOAD_STAGE/'' || :clean_path;
    
    LET distinct_query VARCHAR := ''SELECT ARRAY_AGG(DISTINCT val) FROM (SELECT NULLIF(TRIM($'' || :COLUMN_POSITION::VARCHAR || ''), '''''''') AS val FROM '' || :full_stage || '' (FILE_FORMAT => ''''ACME_FINANCE.INGESTION.CSV_FF_READ'''') WHERE val IS NOT NULL)'';
    LET rs1 RESULTSET := (EXECUTE IMMEDIATE :distinct_query);
    LET cur1 CURSOR FOR rs1;
    OPEN cur1;
    FETCH cur1 INTO distinct_values;
    CLOSE cur1;
    
    IF (:distinct_values IS NULL OR ARRAY_SIZE(:distinct_values) = 0) THEN
        RETURN OBJECT_CONSTRUCT(''error'', ''No distinct values found'', ''resolution_map'', OBJECT_CONSTRUCT());
    END IF;
    
    -- Check cache
    LET sorted_vals VARCHAR := (SELECT LISTAGG(LOWER(f.value::VARCHAR), ''|'') WITHIN GROUP (ORDER BY LOWER(f.value::VARCHAR)) FROM TABLE(FLATTEN(INPUT => :distinct_values)) f);
    cache_hash := SHA2(:sorted_vals || ''|'' || :TARGET_COLUMN);
    
    LET cache_count NUMBER := (SELECT COUNT(*) FROM ACME_FINANCE.INGESTION.VALUE_RESOLUTION_CACHE WHERE SOURCE_VALUES_HASH = :cache_hash);
    
    IF (:cache_count > 0) THEN
        LET cached_map VARIANT := (SELECT RESOLUTION_MAP FROM ACME_FINANCE.INGESTION.VALUE_RESOLUTION_CACHE WHERE SOURCE_VALUES_HASH = :cache_hash ORDER BY CREATED_AT DESC LIMIT 1);
        UPDATE ACME_FINANCE.INGESTION.VALUE_RESOLUTION_CACHE SET TIMES_USED = COALESCE(TIMES_USED, 0) + 1 WHERE SOURCE_VALUES_HASH = :cache_hash;
        RETURN OBJECT_CONSTRUCT(''resolution_map'', :cached_map, ''source'', ''cache'', ''distinct_count'', ARRAY_SIZE(:distinct_values));
    END IF;
    
    -- Guard: if REF_TABLE_NAME is empty/null, return empty map immediately
    IF (:REF_TABLE_NAME IS NULL OR TRIM(:REF_TABLE_NAME) = '''') THEN
        RETURN OBJECT_CONSTRUCT(''resolution_map'', OBJECT_CONSTRUCT(), ''source'', ''skip'', ''distinct_count'', ARRAY_SIZE(:distinct_values), ''error'', ''Empty ref table name'');
    END IF;

    -- Get reference values
    LET ref_col VARCHAR := CASE 
        WHEN :REF_TABLE_NAME = ''REF_EXPENSE_CATEGORIES'' THEN ''CATEGORY_NAME''
        WHEN :REF_TABLE_NAME = ''REF_VENDORS'' THEN ''VENDOR_NAME''
        WHEN :REF_TABLE_NAME = ''REF_GL_ACCOUNTS'' THEN ''GL_ACCOUNT_NAME''
        WHEN :REF_TABLE_NAME = ''REF_DEPARTMENTS'' THEN ''DEPARTMENT_NAME''
        WHEN :REF_TABLE_NAME = ''REF_COST_CENTERS'' THEN ''COST_CENTER_NAME''
        WHEN :REF_TABLE_NAME = ''REF_PAYMENT_METHODS'' THEN ''METHOD_NAME''
        ELSE ''COLUMN1''
    END;
    LET ref_query VARCHAR := ''SELECT ARRAY_AGG(DISTINCT '' || :ref_col || '') FROM ACME_FINANCE.INGESTION.'' || :REF_TABLE_NAME;
    LET rs2 RESULTSET := (EXECUTE IMMEDIATE :ref_query);
    LET cur2 CURSOR FOR rs2;
    OPEN cur2;
    FETCH cur2 INTO ref_values;
    CLOSE cur2;
    
    -- Call AI with structured output
    LET source_list VARCHAR := (SELECT LISTAGG(f.value::VARCHAR, '', '') WITHIN GROUP (ORDER BY f.index) FROM TABLE(FLATTEN(INPUT => ARRAY_SLICE(:distinct_values, 0, 30))) f);
    LET ref_list VARCHAR := (SELECT LISTAGG(f.value::VARCHAR, '', '') WITHIN GROUP (ORDER BY f.index) FROM TABLE(FLATTEN(INPUT => ARRAY_SLICE(:ref_values, 0, 50))) f);
    
    LET prompt VARCHAR := ''Match each source value to the closest canonical value. Source values: '' || :source_list || ''. Canonical values: '' || :ref_list || ''. Match by semantic meaning (description to category). Set canonical_value to null if no reasonable match.'';
    
    LET llm_result VARIANT := (SELECT ACME_FINANCE.INGESTION.AI_RESOLVE_VALUES(:prompt));
    
    -- Convert array to object map
    resolution_map := (
        SELECT OBJECT_AGG(m.value:source_value::VARCHAR, m.value:canonical_value::VARIANT)
        FROM TABLE(FLATTEN(INPUT => :llm_result:mappings)) m
        WHERE m.value:source_value IS NOT NULL
    );
    
    -- Cache
    INSERT INTO ACME_FINANCE.INGESTION.VALUE_RESOLUTION_CACHE (SOURCE_VALUES_HASH, TARGET_COLUMN, REF_TABLE, RESOLUTION_MAP, DISTINCT_COUNT)
        SELECT :cache_hash, :TARGET_COLUMN, :REF_TABLE_NAME, :resolution_map, ARRAY_SIZE(:distinct_values);
    
    RETURN OBJECT_CONSTRUCT(''resolution_map'', :resolution_map, ''source'', ''llm'', ''distinct_count'', ARRAY_SIZE(:distinct_values));
END;
';

-- PREVIEW_RESOLUTION
-- Agent-facing tool for Step 4 (Ambiguity Check).
CREATE OR REPLACE PROCEDURE PREVIEW_RESOLUTION(FILE_PATH VARCHAR, COLUMN_NAME VARCHAR, COLUMN_POSITION NUMBER(38,0), REF_TABLE_NAME VARCHAR, TARGET_COLUMN VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
    resolve_result VARIANT;
BEGIN
    CALL ACME_FINANCE.INGESTION.SP_RESOLVE_COLUMN_VALUES(
        :FILE_PATH, :COLUMN_POSITION, :REF_TABLE_NAME, :TARGET_COLUMN
    ) INTO :resolve_result;
    
    IF (:resolve_result:error IS NOT NULL) THEN
        RETURN ''ERROR: '' || :resolve_result:error::VARCHAR;
    END IF;
    
    LET res_map VARIANT := :resolve_result:resolution_map;
    LET source_type VARCHAR := COALESCE(:resolve_result:source::VARCHAR, ''llm'');
    LET distinct_count NUMBER := COALESCE(:resolve_result:distinct_count::NUMBER, 0);
    
    LET output VARCHAR := ''RESOLUTION PREVIEW — DISPLAY THIS ENTIRE TABLE TO THE USER:\n\n'';
    output := :output || ''| Source Value | Resolved To |\n'';
    output := :output || ''|---|---|\n'';
    
    LET keys VARIANT := OBJECT_KEYS(:res_map);
    LET i NUMBER := 0;
    LET mapped_count NUMBER := 0;
    LET unmapped_count NUMBER := 0;
    
    WHILE (i < ARRAY_SIZE(:keys)) DO
        LET src_val VARCHAR := GET(:keys, :i)::VARCHAR;
        LET tgt_val VARCHAR := GET(:res_map, :src_val)::VARCHAR;
        IF (:tgt_val IS NOT NULL AND :tgt_val != ''null'') THEN
            output := :output || ''| '' || :src_val || '' | '' || :tgt_val || '' |\n'';
            mapped_count := :mapped_count + 1;
        ELSE
            output := :output || ''| '' || :src_val || '' | NO MATCH |\n'';
            unmapped_count := :unmapped_count + 1;
        END IF;
        i := :i + 1;
    END WHILE;
    
    output := :output || ''\n'' || :mapped_count::VARCHAR || '' matched, '' || :unmapped_count::VARCHAR || '' unmatched out of '' || :distinct_count::VARCHAR || '' distinct values.'';
    output := :output || '' (Source: '' || :source_type || '')'';
    
    IF (:unmapped_count > 0) THEN
        output := :output || ''\n\nASK USER: Some values could not be matched. What should they map to?'';
    ELSE
        output := :output || ''\n\nASK USER: Do these resolutions look correct? Approve or request changes.'';
    END IF;
    
    RETURN :output;
END;
';

-- =============================================================================
-- STORED PROCEDURES — Execution
-- =============================================================================

-- SP_BUILD_AND_EXECUTE_COPY_INTO
-- Deterministically builds and executes a COPY INTO statement from the operations enum.
-- NO LLM is involved — pure SQL generation from a mapping spec.
CREATE OR REPLACE PROCEDURE SP_BUILD_AND_EXECUTE_COPY_INTO(PROFILE VARIANT, COLUMN_MAP VARIANT, TARGET_TABLE VARCHAR, STAGE_PATH VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
    col_names    VARIANT;
    copy_sql     VARCHAR;
    target_cols  VARCHAR DEFAULT '''';
    select_exprs VARCHAR DEFAULT '''';
    num_mapped   NUMBER DEFAULT 0;
    rows_loaded  NUMBER DEFAULT 0;
    rows_parsed  NUMBER DEFAULT 0;
    errors_seen  NUMBER DEFAULT 0;
    first_error  VARCHAR DEFAULT '''';
    error_msg    VARCHAR DEFAULT '''';
    run_id       VARCHAR;
    full_target  VARCHAR;
    full_stage   VARCHAR;
BEGIN
    run_id := UUID_STRING();
    col_names := :PROFILE:column_names;
    -- Strip any embedded quotes from target table name (LLM may include them)
    LET clean_target VARCHAR := REPLACE(REPLACE(:TARGET_TABLE, ''"'', ''''), '''''''', '''');
    full_target := ''ACME_FINANCE.INGESTION.'' || :clean_target;
    
    LET clean_path VARCHAR := REPLACE(REPLACE(:STAGE_PATH, ''@UPLOAD_STAGE/'', ''''), ''@ACME_FINANCE.INGESTION.UPLOAD_STAGE/'', '''');
    full_stage := ''@ACME_FINANCE.INGESTION.UPLOAD_STAGE/'' || :clean_path;

    -- Set session to auto-detect all date formats
    EXECUTE IMMEDIATE ''ALTER SESSION SET DATE_INPUT_FORMAT = ''''AUTO'''''';

    LET is_array BOOLEAN := (SELECT TYPEOF(:COLUMN_MAP) = ''ARRAY'');
    LET mappings VARIANT;
    
    IF (:is_array) THEN
        mappings := :COLUMN_MAP;
    ELSE
        LET arr VARIANT := ARRAY_CONSTRUCT();
        LET keys VARIANT := OBJECT_KEYS(:COLUMN_MAP);
        LET ki NUMBER := 0;
        WHILE (ki < ARRAY_SIZE(:keys)) DO
            LET k VARCHAR := GET(:keys, :ki)::VARCHAR;
            arr := ARRAY_APPEND(:arr, OBJECT_CONSTRUCT(''source'', :k, ''dest'', GET(:COLUMN_MAP, :k)::VARCHAR, ''operation'', ''TRIM''));
            ki := :ki + 1;
        END WHILE;
        mappings := :arr;
    END IF;

    LET map_size NUMBER := ARRAY_SIZE(:mappings);
    LET i NUMBER := 0;

    WHILE (i < :map_size) DO
        LET mapping VARIANT := GET(:mappings, :i);
        LET src_col VARCHAR := :mapping:source::VARCHAR;
        LET tgt_col VARCHAR := REPLACE(:mapping:dest::VARCHAR, ''"'', '''');
        LET operation VARCHAR := COALESCE(:mapping:operation::VARCHAR, ''TRIM'');
        LET ref_table VARCHAR := :mapping:ref_table::VARCHAR;

        -- Strip quotes and validate dest column name
        tgt_col := NULLIF(TRIM(:tgt_col), '''');

        LET pos NUMBER := -1;
        LET j NUMBER := 0;
        LET num_cols NUMBER := ARRAY_SIZE(:col_names);
        WHILE (j < :num_cols) DO
            IF (GET(:col_names, :j)::VARCHAR = :src_col) THEN
                pos := :j + 1;
            END IF;
            j := :j + 1;
        END WHILE;

        IF (:pos > 0 AND :tgt_col IS NOT NULL) THEN
            LET expr VARCHAR;
            LET p VARCHAR := :pos::VARCHAR;

            IF (:operation = ''NUMERIC_STRIP_UNITS'') THEN
                expr := ''TRY_TO_NUMBER(REGEXP_REPLACE(REPLACE($'' || :p || '', ''''~'''', ''''''''), ''''[^0-9.]'''', ''''''''))'';
            ELSEIF (:operation = ''TO_DATE'') THEN
                expr := ''TRY_TO_DATE(TRIM($'' || :p || ''))'';
            ELSEIF (:operation = ''TO_DATE_START'') THEN
                expr := ''TRY_TO_DATE(TRIM(SPLIT_PART(REGEXP_REPLACE($'' || :p || '', '''' – | - '''', '''' to ''''), '''' to '''', 1)))'';
            ELSEIF (:operation = ''TO_DATE_END'') THEN
                expr := ''COALESCE(TRY_TO_DATE(NULLIF(TRIM(SPLIT_PART(REGEXP_REPLACE($'' || :p || '', '''' – | - '''', '''' to ''''), '''' to '''', 2)), '''''''')), TRY_TO_DATE(TRIM(SPLIT_PART(REGEXP_REPLACE($'' || :p || '', '''' – | - '''', '''' to ''''), '''' to '''', 1))))'';
            ELSEIF (:operation = ''TO_NUMBER'') THEN
                expr := ''TRY_TO_NUMBER($'' || :p || '')'';
            ELSEIF (:operation = ''DIRECT'') THEN
                expr := ''$'' || :p;
            ELSEIF (:operation = ''RESOLVE_ENTITY'') THEN
                LET resolve_ref VARCHAR := COALESCE(NULLIF(TRIM(:ref_table), ''''), ''REF_EXPENSE_CATEGORIES'');
                LET resolve_result VARIANT;
                CALL ACME_FINANCE.INGESTION.SP_RESOLVE_COLUMN_VALUES(
                    :STAGE_PATH, :pos, :resolve_ref, :tgt_col
                ) INTO :resolve_result;
                
                LET res_map VARIANT := :resolve_result:resolution_map;
                IF (:res_map IS NOT NULL AND ARRAY_SIZE(OBJECT_KEYS(:res_map)) > 0) THEN
                    LET case_expr VARCHAR := ''CASE '';
                    LET res_keys VARIANT := OBJECT_KEYS(:res_map);
                    LET rk NUMBER := 0;
                    LET has_when BOOLEAN := FALSE;
                    WHILE (rk < ARRAY_SIZE(:res_keys)) DO
                        LET src_val VARCHAR := GET(:res_keys, :rk)::VARCHAR;
                        LET tgt_val VARCHAR := GET(:res_map, :src_val)::VARCHAR;
                        IF (:tgt_val IS NOT NULL AND :tgt_val != ''null'') THEN
                            case_expr := :case_expr || ''WHEN TRIM($'' || :p || '') = '''''' || REPLACE(:src_val, '''''''', '''''''''''') || '''''' THEN '''''' || REPLACE(:tgt_val, '''''''', '''''''''''') || '''''' '';
                            has_when := TRUE;
                        END IF;
                        rk := :rk + 1;
                    END WHILE;
                    IF (:has_when) THEN
                        case_expr := :case_expr || ''ELSE NULLIF(TRIM($'' || :p || ''), '''''''') END'';
                        expr := :case_expr;
                    ELSE
                        -- No valid WHEN clauses generated — fall back to TRIM
                        expr := ''NULLIF(TRIM($'' || :p || ''), '''''''')'';
                    END IF;
                ELSE
                    -- Resolution map is null or empty — fall back to TRIM
                    expr := ''NULLIF(TRIM($'' || :p || ''), '''''''')'';
                END IF;
            ELSE
                expr := ''NULLIF(TRIM($'' || :p || ''), '''''''')'';
            END IF;

            IF (:num_mapped > 0) THEN
                target_cols := :target_cols || '', '';
                select_exprs := :select_exprs || '', '';
            END IF;
            target_cols := :target_cols || :tgt_col;
            select_exprs := :select_exprs || :expr;
            num_mapped := :num_mapped + 1;
        END IF;

        i := :i + 1;
    END WHILE;

    IF (:num_mapped = 0) THEN
        RETURN OBJECT_CONSTRUCT(''run_id'', :run_id, ''rows_loaded'', 0, ''error'', ''No valid column mappings'', ''copy_sql'', NULL);
    END IF;

    copy_sql := ''COPY INTO '' || :full_target || '' ('' || :target_cols || '') FROM (SELECT '' || :select_exprs || '' FROM '' || :full_stage || '' (FILE_FORMAT => ''''ACME_FINANCE.INGESTION.CSV_FF_READ'''')) FORCE = TRUE ON_ERROR = CONTINUE'';

    BEGIN
        EXECUTE IMMEDIATE :copy_sql;
        LET copy_result RESULTSET := (EXECUTE IMMEDIATE ''SELECT "rows_parsed", "rows_loaded", "errors_seen", "first_error" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))'');
        LET copy_cur CURSOR FOR copy_result;
        OPEN copy_cur;
        FETCH copy_cur INTO rows_parsed, rows_loaded, errors_seen, first_error;
        CLOSE copy_cur;
    EXCEPTION
        WHEN OTHER THEN
            error_msg := SQLERRM;
    END;

    BEGIN
        INSERT INTO ACME_FINANCE.INGESTION.RUN_HISTORY (RUN_ID, STAGE_PATH, TARGET_TABLE, ROWS_LOADED, ROWS_REJECTED, STATUS, ERRORS)
            SELECT :run_id, :STAGE_PATH, :TARGET_TABLE, :rows_loaded, :errors_seen,
                   CASE WHEN :error_msg = '''' AND :errors_seen = 0 THEN ''success'' 
                        WHEN :error_msg = '''' AND :errors_seen > 0 THEN ''partial''
                        ELSE ''failed'' END,
                   NULLIF(COALESCE(:error_msg, '''') || CASE WHEN :first_error IS NOT NULL THEN '' | First error: '' || :first_error ELSE '''' END, '''');
    EXCEPTION
        WHEN OTHER THEN NULL;
    END;

    RETURN OBJECT_CONSTRUCT(
        ''run_id'', :run_id,
        ''rows_parsed'', :rows_parsed,
        ''rows_loaded'', :rows_loaded,
        ''rows_rejected'', :errors_seen,
        ''first_error'', :first_error,
        ''error'', NULLIF(:error_msg, ''''),
        ''copy_sql'', :copy_sql
    );
END;
';


-- EXECUTE_MAPPING
-- Agent-facing tool called in Step 6 after user approval.
CREATE OR REPLACE PROCEDURE EXECUTE_MAPPING(MAPPING_JSON VARCHAR, FILE_PATH VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
    parsed VARIANT;
    target_table VARCHAR;
    profile VARIANT;
    mappings VARIANT;
    result VARIANT;
BEGIN
    parsed := PARSE_JSON(:MAPPING_JSON);
    target_table := :parsed:target_table::VARCHAR;
    mappings := :parsed:mappings;
    
    CALL ACME_FINANCE.INGESTION.SP_PROFILE_STAGED_FILE(:FILE_PATH) INTO :profile;
    
    CALL ACME_FINANCE.INGESTION.SP_BUILD_AND_EXECUTE_COPY_INTO(
        :profile, :mappings, :target_table, :FILE_PATH
    ) INTO :result;
    
    -- Save config on success
    IF (:result:error IS NULL AND :result:rows_loaded::NUMBER > 0) THEN
        LET col_names VARIANT := :profile:column_names;
        LET sorted_sig VARCHAR := (
            SELECT LISTAGG(LOWER(f.value::VARCHAR), ''|'') WITHIN GROUP (ORDER BY LOWER(f.value::VARCHAR))
            FROM TABLE(FLATTEN(INPUT => :col_names)) f
        );
        LET col_hash VARCHAR := SHA2(:sorted_sig);
        
        LET existing_count NUMBER := (
            SELECT COUNT(*) FROM ACME_FINANCE.INGESTION.MAPPING_CONFIGS
            WHERE SOURCE_COLUMN_HASH = :col_hash
        );
        
        IF (:existing_count = 0) THEN
            INSERT INTO ACME_FINANCE.INGESTION.MAPPING_CONFIGS
                (CONFIG_ID, SOURCE_COLUMN_HASH, SOURCE_COLUMN_SIGNATURE, TARGET_TABLE, COLUMN_MAP)
            SELECT UUID_STRING(), :col_hash, :col_names, :target_table, :mappings;
        END IF;
    END IF;
    
    -- Build response
    LET response VARCHAR := ''## Execution Results\n\n'';
    response := :response || ''- **Target:** ACME_FINANCE.INGESTION.'' || :target_table || ''\n'';
    response := :response || ''- **Rows parsed:** '' || COALESCE(:result:rows_parsed::VARCHAR, ''?'') || ''\n'';
    response := :response || ''- **Rows loaded:** '' || COALESCE(:result:rows_loaded::VARCHAR, ''0'') || ''\n'';
    response := :response || ''- **Rows rejected:** '' || COALESCE(:result:rows_rejected::VARCHAR, ''0'') || ''\n'';
    
    IF (:result:rows_rejected::NUMBER > 0) THEN
        response := :response || ''- **First error:** '' || COALESCE(:result:first_error::VARCHAR, ''unknown'') || ''\n'';
    END IF;
    
    IF (:result:error IS NOT NULL) THEN
        response := :response || ''- **Execution error:** '' || :result:error::VARCHAR || ''\n'';
    END IF;
    
    -- Show sample of loaded data
    IF (:result:rows_loaded::NUMBER > 0) THEN
        response := :response || ''\n## Sample of Loaded Data (first 10 rows)\n\n'';
        
        BEGIN
            LET col_query VARCHAR := ''SELECT LISTAGG(COLUMN_NAME, '''' | '''') WITHIN GROUP (ORDER BY ORDINAL_POSITION) FROM ACME_FINANCE.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ''''INGESTION'''' AND TABLE_CATALOG = ''''ACME_FINANCE'''' AND TABLE_NAME = '''''' || :target_table || '''''''';
            LET headers VARCHAR;
            LET rs_h RESULTSET := (EXECUTE IMMEDIATE :col_query);
            LET cur_h CURSOR FOR rs_h;
            OPEN cur_h;
            FETCH cur_h INTO headers;
            CLOSE cur_h;
            
            LET rows_query VARCHAR := ''SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*)) FROM (SELECT * FROM ACME_FINANCE.INGESTION.'' || :target_table || '' ORDER BY 1 DESC NULLS LAST LIMIT 10)'';
            LET rows_arr VARIANT;
            LET rs_r RESULTSET := (EXECUTE IMMEDIATE :rows_query);
            LET cur_r CURSOR FOR rs_r;
            OPEN cur_r;
            FETCH cur_r INTO rows_arr;
            CLOSE cur_r;
            
            IF (:rows_arr IS NOT NULL AND ARRAY_SIZE(:rows_arr) > 0) THEN
                LET ri NUMBER := 0;
                WHILE (ri < ARRAY_SIZE(:rows_arr) AND ri < 10) DO
                    LET row_obj VARIANT := GET(:rows_arr, :ri);
                    LET row_text VARCHAR := ''**Row '' || (:ri + 1)::VARCHAR || '':** '';
                    LET row_keys VARIANT := OBJECT_KEYS(:row_obj);
                    LET rk NUMBER := 0;
                    WHILE (rk < ARRAY_SIZE(:row_keys)) DO
                        LET col_name VARCHAR := GET(:row_keys, :rk)::VARCHAR;
                        LET col_val VARCHAR := COALESCE(GET(:row_obj, :col_name)::VARCHAR, ''NULL'');
                        IF (:col_val != ''NULL'' AND :col_val != '''') THEN
                            row_text := :row_text || :col_name || ''='' || :col_val || '' | '';
                        END IF;
                        rk := :rk + 1;
                    END WHILE;
                    response := :response || :row_text || ''\n'';
                    ri := :ri + 1;
                END WHILE;
            END IF;
        EXCEPTION
            WHEN OTHER THEN
                response := :response || ''(Could not retrieve sample: '' || SQLERRM || '')\n'';
        END;
    END IF;
    
    response := :response || ''\n## SQL Executed\n\n'' || COALESCE(:result:copy_sql::VARCHAR, ''N/A'');
    
    RETURN :response;
END;
';

-- =============================================================================
-- CORTEX AGENT
-- =============================================================================

CREATE OR REPLACE AGENT ACME_FINANCE.INGESTION.SCHEMA_MAPPER_AGENT
COMMENT = 'Schema mapper agent for mapping messy CSV uploads to canonical financial tables'
PROFILE = '{"display_name": "Schema Mapper Agent", "color": "blue"}'
FROM SPECIFICATION $$
{
  "models": {"orchestration": "auto"},
  "orchestration": {"budget": {"seconds": 180, "tokens": 15000}},
  "instructions": {
    "response": "You are the Schema Mapper Agent. You help users map messy CSV data into canonical financial tables (mileage claims, purchase expenses, vendor invoices).\n\nWORKFLOW (follow these steps IN ORDER — do NOT skip any):\n\nStep 1 - FILE DISCOVERY:\nCall list_staged_files to show available files. Confirm which file the user wants to process.\n\nStep 2 - PROFILING:\nCall profile_file with the filename. Present results clearly.\n\nStep 3 - MAPPING PROPOSAL:\nCall propose_mapping with the profile text. Present the mapping as a readable table showing:\n- Source Column → Target Column (Operation)\n- Ignored source columns (and why)\n- **UNMAPPED TARGET COLUMNS** — list which canonical table columns will be LEFT EMPTY because no source column maps to them. This is critical for the user to understand data completeness.\n\nStep 4 - AMBIGUITY CHECK (CRITICAL):\na) MISSING UNITS: If numeric sample values have no embedded currency/unit, ASK the user what currency/unit the data is in.\nb) ENTITY RESOLUTION: For EVERY RESOLVE_ENTITY column, call preview_resolution. Show the FULL resolution table to the user. Ask if resolutions look correct.\nc) UNMATCHED VALUES: If any values show NO MATCH, ask the user what they should map to.\n\nStep 5 - USER APPROVAL:\nPresent the FINAL mapping and ask for explicit approval. NEVER skip this step.\n\nStep 6 - EXECUTION:\nOnly after user confirms, call execute_mapping. Report results and show sample data.\n\nRULES:\n- NEVER skip Steps 4 or 5.\n- Always show unmapped target columns so user knows what will be empty.\n- Always show entity resolution previews before executing.\n- If data has no embedded currency or unit, ASK what they are.\n",
    "orchestration": "Follow workflow steps in order. After propose_mapping, ALWAYS check for ambiguities. Call preview_resolution for RESOLVE_ENTITY columns. Show unmapped target columns. Get explicit approval before execute_mapping.\n"
  },
  "tools": [
    {
      "tool_spec": {
        "type": "generic",
        "name": "list_staged_files",
        "description": "Lists all CSV files on the upload stage.",
        "input_schema": {"type": "object", "properties": {}}
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "profile_file",
        "description": "Profiles a CSV file. Returns columns, types, cardinality, null rates, samples.",
        "input_schema": {"type": "object", "properties": {"file_path": {"type": "string", "description": "Filename on stage"}}, "required": ["file_path"]}
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "get_target_schemas",
        "description": "Returns available target tables and their column names.",
        "input_schema": {"type": "object", "properties": {}}
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "propose_mapping",
        "description": "Proposes a column mapping. Returns JSON with mappings, ignored columns, AND unmapped_target_columns.",
        "input_schema": {"type": "object", "properties": {"profile_text": {"type": "string", "description": "Profile text from profile_file"}}, "required": ["profile_text"]}
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "preview_resolution",
        "description": "Shows how each distinct value resolves to canonical values. Call for EVERY RESOLVE_ENTITY column BEFORE approval.",
        "input_schema": {"type": "object", "properties": {"file_path": {"type": "string", "description": "Filename on stage"}, "column_name": {"type": "string", "description": "Source column name"}, "column_position": {"type": "integer", "description": "1-based position in CSV"}, "ref_table_name": {"type": "string", "description": "Reference table (e.g., REF_EXPENSE_CATEGORIES)"}, "target_column": {"type": "string", "description": "Target column (e.g., EXPENSE_CATEGORY)"}}, "required": ["file_path", "column_name", "column_position", "ref_table_name", "target_column"]}
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "execute_mapping",
        "description": "Executes approved mapping. Shows loaded data sample. ONLY call after user confirms.",
        "input_schema": {"type": "object", "properties": {"mapping_json": {"type": "string", "description": "JSON mapping with target_table and mappings array"}, "file_path": {"type": "string", "description": "Filename on stage"}}, "required": ["mapping_json", "file_path"]}
      }
    }
  ],
  "tool_resources": {
    "list_staged_files": {"type": "function", "execution_environment": {"type": "warehouse", "warehouse": "COMPUTE_WH"}, "identifier": "ACME_FINANCE.INGESTION.LIST_STAGED_FILES"},
    "profile_file": {"type": "procedure", "execution_environment": {"type": "warehouse", "warehouse": "COMPUTE_WH"}, "identifier": "ACME_FINANCE.INGESTION.PROFILE_FILE"},
    "get_target_schemas": {"type": "function", "execution_environment": {"type": "warehouse", "warehouse": "COMPUTE_WH"}, "identifier": "ACME_FINANCE.INGESTION.GET_TARGET_SCHEMAS"},
    "propose_mapping": {"type": "procedure", "execution_environment": {"type": "warehouse", "warehouse": "COMPUTE_WH", "query_timeout": 60}, "identifier": "ACME_FINANCE.INGESTION.PROPOSE_MAPPING"},
    "preview_resolution": {"type": "procedure", "execution_environment": {"type": "warehouse", "warehouse": "COMPUTE_WH", "query_timeout": 60}, "identifier": "ACME_FINANCE.INGESTION.PREVIEW_RESOLUTION"},
    "execute_mapping": {"type": "procedure", "execution_environment": {"type": "warehouse", "warehouse": "COMPUTE_WH", "query_timeout": 60}, "identifier": "ACME_FINANCE.INGESTION.EXECUTE_MAPPING"}
  }
}
$$
;

-- =============================================================================
-- STAGE CONFIGURATION
-- =============================================================================

ALTER STAGE ACME_FINANCE.INGESTION.UPLOAD_STAGE SET DIRECTORY = (ENABLE = TRUE);
ALTER STAGE ACME_FINANCE.INGESTION.UPLOAD_STAGE REFRESH;
