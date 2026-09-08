-- 05_automation.sql
-- Creates stream, stored procedure, and task for automated processing.
-- Pre-split slip PDFs uploaded to @SPLIT_SLIPS trigger the full pipeline.
USE SCHEMA PACKING_SLIP_PROCESSING.PACKING_SLIPS;

-- Stream watches the SPLIT_SLIPS stage for new individual slip files
CREATE OR REPLACE STREAM NEW_DOCUMENTS_STREAM ON STAGE SPLIT_SLIPS;

-- Stored procedure: processes each new PDF end-to-end
-- 1. AI_PARSE_DOCUMENT for OCR text
-- 2. AI_COMPLETE (claude-sonnet-4-6) for structured extraction
-- 3. Flatten into headers + line items
-- 4. Confidence scoring (two separate UPDATEs to avoid pre-update value bug)
-- 5. Set PAGE_FILE for Streamlit PDF rendering
-- Errors are caught per-file and logged to EXTRACTION_ERRORS.
CREATE OR REPLACE PROCEDURE PROCESS_NEW_DOCUMENTS()
    RETURNS VARCHAR
    LANGUAGE SQL
    EXECUTE AS OWNER
AS
$$
DECLARE
    files_processed NUMBER DEFAULT 0;
    files_errored NUMBER DEFAULT 0;
    current_file VARCHAR;
    cur CURSOR FOR
        SELECT RELATIVE_PATH
        FROM PACKING_SLIP_PROCESSING.PACKING_SLIPS.NEW_DOCUMENTS_STREAM
        WHERE METADATA$ACTION = 'INSERT'
          AND RELATIVE_PATH LIKE '%.pdf';
BEGIN
    FOR rec IN cur DO
        current_file := rec.RELATIVE_PATH;
        BEGIN
            -- Step 1: OCR the document
            INSERT INTO PACKING_SLIP_PROCESSING.PACKING_SLIPS.PARSED_DOCUMENTS
                (FILE_NAME, RELATIVE_PATH, PARSED_CONTENT)
            SELECT :current_file, :current_file,
                AI_PARSE_DOCUMENT(
                    TO_FILE('@PACKING_SLIP_PROCESSING.PACKING_SLIPS.SPLIT_SLIPS', :current_file),
                    {'mode': 'LAYOUT'}
                ):content::VARCHAR;

            -- Step 2: Extract with AI_COMPLETE
            INSERT INTO PACKING_SLIP_PROCESSING.PACKING_SLIPS.AI_COMPLETE_EXTRACTIONS
                (FILE_NAME, RELATIVE_PATH, RAW_RESPONSE)
            SELECT :current_file, :current_file,
                AI_COMPLETE(
                    'claude-sonnet-4-6',
                    [{'role': 'user', 'content': 'Extract ALL packing slips from this OCR text as a JSON array. For each slip include: approximate_page (int), po_number, supplier_name (NOT Summit Industries), shipment_number, shipment_date (YYYY-MM-DD), ship_to_address (delivery destination, usually Springfield IL), bill_to_address (invoicing, usually Springfield IL), carrier, tracking_number, received_date (YYYY-MM-DD), received_by, line_items (array of {part_number, description, quantity_ordered, quantity_shipped, unit_of_measure}). Return ONLY JSON array, no markdown.

DOCUMENT:
' || (SELECT PARSED_CONTENT FROM PACKING_SLIP_PROCESSING.PACKING_SLIPS.PARSED_DOCUMENTS WHERE RELATIVE_PATH = :current_file ORDER BY PARSED_AT DESC LIMIT 1)}],
                    {'max_tokens': 16384}
                );

            -- Step 3: Parse JSON
            UPDATE PACKING_SLIP_PROCESSING.PACKING_SLIPS.AI_COMPLETE_EXTRACTIONS
            SET PARSED_JSON = TRY_PARSE_JSON(
                CASE
                    WHEN RAW_RESPONSE LIKE '```json%' THEN TRIM(REGEXP_REPLACE(RAW_RESPONSE, '^```json\\s*|\\s*```\\s*$', ''))
                    WHEN RAW_RESPONSE LIKE '```%' THEN TRIM(REGEXP_REPLACE(RAW_RESPONSE, '^```\\s*|\\s*```\\s*$', ''))
                    ELSE TRIM(RAW_RESPONSE)
                END
            ),
            SLIP_COUNT = ARRAY_SIZE(TRY_PARSE_JSON(
                CASE
                    WHEN RAW_RESPONSE LIKE '```json%' THEN TRIM(REGEXP_REPLACE(RAW_RESPONSE, '^```json\\s*|\\s*```\\s*$', ''))
                    WHEN RAW_RESPONSE LIKE '```%' THEN TRIM(REGEXP_REPLACE(RAW_RESPONSE, '^```\\s*|\\s*```\\s*$', ''))
                    ELSE TRIM(RAW_RESPONSE)
                END
            ))
            WHERE FILE_NAME = :current_file AND PARSED_JSON IS NULL;

            -- Step 4: Flatten into headers
            LET ext_id NUMBER := (SELECT MAX(EXTRACTION_ID) FROM PACKING_SLIP_PROCESSING.PACKING_SLIPS.AI_COMPLETE_EXTRACTIONS WHERE FILE_NAME = :current_file);

            INSERT INTO PACKING_SLIP_PROCESSING.PACKING_SLIPS.PACKING_SLIP_HEADERS (
                EXTRACTION_ID, SLIP_INDEX, FILE_NAME, PAGE_NUMBER, PAGE_FILE,
                PO_NUMBER, SUPPLIER_NAME, SHIPMENT_NUMBER, SHIPMENT_DATE,
                SHIP_TO_ADDRESS, BILL_TO_ADDRESS, CARRIER, TRACKING_NUMBER,
                RECEIVED_DATE, RECEIVED_BY
            )
            SELECT :ext_id, f.INDEX, :current_file, f.VALUE:approximate_page::NUMBER,
                :current_file,
                f.VALUE:po_number::VARCHAR, f.VALUE:supplier_name::VARCHAR,
                f.VALUE:shipment_number::VARCHAR, f.VALUE:shipment_date::VARCHAR,
                f.VALUE:ship_to_address::VARCHAR, f.VALUE:bill_to_address::VARCHAR,
                f.VALUE:carrier::VARCHAR, f.VALUE:tracking_number::VARCHAR,
                f.VALUE:received_date::VARCHAR, f.VALUE:received_by::VARCHAR
            FROM PACKING_SLIP_PROCESSING.PACKING_SLIPS.AI_COMPLETE_EXTRACTIONS e,
                LATERAL FLATTEN(input => e.PARSED_JSON) f
            WHERE e.EXTRACTION_ID = :ext_id;

            -- Step 5: Flatten line items
            INSERT INTO PACKING_SLIP_PROCESSING.PACKING_SLIPS.PACKING_SLIP_LINE_ITEMS (
                HEADER_ID, PART_NUMBER, DESCRIPTION, QUANTITY_ORDERED, QUANTITY_SHIPPED, UNIT_OF_MEASURE
            )
            SELECT h.HEADER_ID,
                li.VALUE:part_number::VARCHAR, li.VALUE:description::VARCHAR,
                li.VALUE:quantity_ordered::VARCHAR, li.VALUE:quantity_shipped::VARCHAR,
                li.VALUE:unit_of_measure::VARCHAR
            FROM PACKING_SLIP_PROCESSING.PACKING_SLIPS.AI_COMPLETE_EXTRACTIONS ext
            CROSS JOIN LATERAL FLATTEN(input => ext.PARSED_JSON) slip
            CROSS JOIN LATERAL FLATTEN(input => slip.VALUE:line_items) li
            JOIN PACKING_SLIP_PROCESSING.PACKING_SLIPS.PACKING_SLIP_HEADERS h
                ON h.EXTRACTION_ID = ext.EXTRACTION_ID AND h.SLIP_INDEX = slip.INDEX
            WHERE ext.EXTRACTION_ID = :ext_id;

            -- Step 6a: Compute confidence score (separate UPDATE)
            UPDATE PACKING_SLIP_PROCESSING.PACKING_SLIPS.PACKING_SLIP_HEADERS h
            SET CONFIDENCE_SCORE = (
                (CASE WHEN PO_NUMBER IS NOT NULL AND PO_NUMBER != '' THEN 1 ELSE 0 END
                + CASE WHEN SUPPLIER_NAME IS NOT NULL AND SUPPLIER_NAME != '' THEN 1 ELSE 0 END
                + CASE WHEN SHIPMENT_DATE IS NOT NULL AND SHIPMENT_DATE != '' THEN 1 ELSE 0 END
                + CASE WHEN SHIP_TO_ADDRESS IS NOT NULL AND SHIP_TO_ADDRESS != '' THEN 1 ELSE 0 END
                + CASE WHEN CARRIER IS NOT NULL AND CARRIER != '' THEN 1 ELSE 0 END
                + CASE WHEN TRACKING_NUMBER IS NOT NULL AND TRACKING_NUMBER != '' THEN 1 ELSE 0 END
                ) / 6.0 * 0.50
                + CASE WHEN PO_NUMBER IS NOT NULL AND REGEXP_LIKE(PO_NUMBER, '^[A-Za-z0-9][A-Za-z0-9\\-]{3,}$') THEN 0.20 ELSE 0.05 END
                + CASE WHEN TRY_TO_DATE(SHIPMENT_DATE) IS NOT NULL THEN 0.15 ELSE 0.03 END
                + CASE WHEN EXISTS (SELECT 1 FROM PACKING_SLIP_PROCESSING.PACKING_SLIPS.PACKING_SLIP_LINE_ITEMS li WHERE li.HEADER_ID = h.HEADER_ID AND li.PART_NUMBER IS NOT NULL) THEN 0.15 ELSE 0 END
            )
            WHERE EXTRACTION_ID = :ext_id;

            -- Step 6b: Set review status based on computed score (separate UPDATE so it reads the new CONFIDENCE_SCORE)
            UPDATE PACKING_SLIP_PROCESSING.PACKING_SLIPS.PACKING_SLIP_HEADERS
            SET REVIEW_STATUS = CASE
                WHEN CONFIDENCE_SCORE >= 0.85 THEN 'AUTO_APPROVED'
                WHEN CONFIDENCE_SCORE < 0.60 THEN 'NEEDS_REVIEW'
                ELSE 'PENDING'
            END
            WHERE EXTRACTION_ID = :ext_id;

            files_processed := files_processed + 1;
        EXCEPTION
            WHEN OTHER THEN
                INSERT INTO PACKING_SLIP_PROCESSING.PACKING_SLIPS.EXTRACTION_ERRORS (FILE_NAME, ERROR_MESSAGE, PIPELINE_STEP)
                SELECT :current_file, SQLERRM, 'PROCESS_NEW_DOCUMENTS';
                files_errored := files_errored + 1;
        END;
    END FOR;
    RETURN 'Processed: ' || :files_processed || ', Errors: ' || :files_errored;
END;
$$;

-- Task: checks the stream every minute, processes new split slip PDFs
CREATE OR REPLACE TASK PROCESS_PACKING_SLIPS_TASK
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '1 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('PACKING_SLIP_PROCESSING.PACKING_SLIPS.NEW_DOCUMENTS_STREAM')
AS
    CALL PACKING_SLIP_PROCESSING.PACKING_SLIPS.PROCESS_NEW_DOCUMENTS();

-- Task starts SUSPENDED. Resume when ready:
-- ALTER TASK PROCESS_PACKING_SLIPS_TASK RESUME;
