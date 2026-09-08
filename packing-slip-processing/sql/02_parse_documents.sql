-- 02_parse_documents.sql
-- Runs AI_PARSE_DOCUMENT (LAYOUT mode) on all PDFs in the stage.
-- Prerequisite: PDFs uploaded to @RAW_DOCS and directory refreshed.
USE SCHEMA PACKING_SLIP_PROCESSING.PACKING_SLIPS;

INSERT INTO PARSED_DOCUMENTS (FILE_NAME, RELATIVE_PATH, PARSED_CONTENT, PAGE_COUNT, PARSE_METADATA)
WITH raw_parsed AS (
    SELECT
        relative_path AS file_name,
        relative_path,
        AI_PARSE_DOCUMENT(
            TO_FILE('@PACKING_SLIP_PROCESSING.PACKING_SLIPS.RAW_DOCS', relative_path),
            {'mode': 'LAYOUT'}
        ) AS parse_result
    FROM DIRECTORY(@PACKING_SLIP_PROCESSING.PACKING_SLIPS.RAW_DOCS)
    WHERE relative_path ILIKE '%.pdf'
      AND relative_path NOT IN (SELECT RELATIVE_PATH FROM PARSED_DOCUMENTS)
)
SELECT
    file_name,
    relative_path,
    parse_result:content::STRING,
    COALESCE(parse_result:metadata:pageCount::INT, parse_result:metadata:page_count::INT, 0),
    parse_result:metadata
FROM raw_parsed;

-- Verify
SELECT FILE_NAME, PAGE_COUNT, LENGTH(PARSED_CONTENT) AS TEXT_LENGTH
FROM PARSED_DOCUMENTS ORDER BY FILE_NAME;
