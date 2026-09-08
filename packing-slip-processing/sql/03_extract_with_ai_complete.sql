-- 03_extract_with_ai_complete.sql
-- Uses AI_COMPLETE (claude-sonnet-4-6) to extract all packing slips and line items
-- from the parsed OCR text. This replaces the earlier AI_EXTRACT approach which
-- could not reliably extract line items from multi-page documents.
USE SCHEMA PACKING_SLIP_PROCESSING.PACKING_SLIPS;

-- Extract all PDFs using AI_COMPLETE with conversation format for max_tokens control
INSERT INTO AI_COMPLETE_EXTRACTIONS (FILE_NAME, RELATIVE_PATH, RAW_RESPONSE)
SELECT
    p.FILE_NAME,
    p.RELATIVE_PATH,
    AI_COMPLETE(
        'claude-sonnet-4-6',
        [{'role': 'user', 'content': 'You are a document extraction expert. Extract ALL packing slips, shipments, bills of lading, and order acknowledgements from this OCR text of a multi-page scanned PDF.

For each distinct document/slip found, return a JSON object with these fields:
- approximate_page: integer page number where this slip starts (1-based)
- po_number: Purchase Order number (string)
- supplier_name: The company shipping TO Summit Industries (NOT Summit Industries itself) (string)
- shipment_number: Shipment/packing slip/W.O. number (string)
- shipment_date: Date in YYYY-MM-DD format (string)
- ship_to_address: Physical delivery destination - usually Summit Distribution Center, 1200 Commerce Blvd, Springfield IL 62701 (string)
- bill_to_address: Invoicing address - usually Summit Industries HQ, 500 Industrial Pkwy, Springfield IL 62704 (string)
- carrier: Shipping carrier name (string)
- tracking_number: Tracking/PRO number (string)
- received_date: Date from RECEIVED stamp YYYY-MM-DD (string)
- received_by: Name from RECEIVED stamp (string)
- line_items: array of objects each with part_number(string), description(string), quantity_ordered(string), quantity_shipped(string), unit_of_measure(string)

Return ONLY a JSON array. No markdown code fences. No explanation text.

DOCUMENT TEXT:
' || p.PARSED_CONTENT}],
        {'max_tokens': 16384}
    ) AS raw_response
FROM PARSED_DOCUMENTS p
WHERE p.FILE_NAME NOT IN (SELECT FILE_NAME FROM AI_COMPLETE_EXTRACTIONS);

-- Parse the JSON response and count slips
UPDATE AI_COMPLETE_EXTRACTIONS
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
WHERE PARSED_JSON IS NULL;

-- Verify
SELECT FILE_NAME, SLIP_COUNT, LENGTH(RAW_RESPONSE) AS RESP_LEN
FROM AI_COMPLETE_EXTRACTIONS ORDER BY FILE_NAME;
