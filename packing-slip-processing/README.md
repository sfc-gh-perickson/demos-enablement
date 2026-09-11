# Packing Slip Extraction Pipeline

> **Enablement Lab** — This project uses sample data and anonymized supplier names
> for hands-on learning. Follow the setup steps below to build and run the full
> pipeline in your own Snowflake account.

Snowflake-native document extraction pipeline that processes packing slip PDFs,
extracts structured fields and line items using AI functions, and provides a
human-in-the-loop Streamlit review app for validation and correction.

## What This Replaces

Manual data entry from scanned packing slips into receiving systems (previously
3-4 hours/day). PDFs are scanned at the receiving dock, split into individual
slip files locally, uploaded to Snowflake, and the pipeline extracts all fields
automatically. A Streamlit app lets staff validate, correct, and approve
extractions before the data flows downstream.

## Architecture

```
PDF files (scanned at dock, multi-page bundles)
    |
    v
split_packing_slips.py (local preprocessing)
    |  - Splits by packing slip boundaries (not pages)
    |  - Uses AI-detected page mapping or local OCR heuristics
    |  - Multi-page slips stay as one file
    |  - Outputs: one PDF per slip + manifest CSV
    |
    v
@SPLIT_SLIPS stage (one file per packing slip)
    |
    v  (stream detects new files)
NEW_DOCUMENTS_STREAM
    |
    v  (task fires every 1 min when stream has data)
PROCESS_NEW_DOCUMENTS() stored procedure
    |
    +---> AI_PARSE_DOCUMENT (LAYOUT mode)     --> PARSED_DOCUMENTS (OCR text)
    +---> AI_COMPLETE (claude-sonnet-4-6)      --> AI_COMPLETE_EXTRACTIONS (JSON)
    +---> LATERAL FLATTEN                      --> PACKING_SLIP_HEADERS
    |                                          --> PACKING_SLIP_LINE_ITEMS
    +---> Confidence scoring                   --> REVIEW_STATUS set per row
    +---> Errors caught per-file               --> EXTRACTION_ERRORS
    |
    v
Streamlit HITL App (review, correct, approve/reject)
    |
    v
RECONCILIATION_VIEW (join against PURCHASE_ORDERS)
```

### Why split locally before upload?

The original multi-page PDFs bundle 20-37 packing slips from different suppliers
into a single file. Without splitting, the review app can't show the right PDF
page for each slip, and the AI extraction has to process massive documents in
one call. Splitting locally:

- Creates a clean 1:1 mapping between files and slips
- Eliminates page sync issues in the review UI
- Reduces per-document AI token usage
- Handles multi-page slips correctly (e.g., a 4-page MRC slip stays as one file)

### Why AI_COMPLETE instead of AI_EXTRACT?

The initial implementation used `AI_EXTRACT` with a table schema. This worked
for header-level fields but failed for line items: only 9 out of hundreds of
expected line items were extracted. `AI_COMPLETE` with `claude-sonnet-4-6`
processes the full OCR text and returns structured JSON with all slips, their
line items, and page numbers.

| Metric | AI_EXTRACT | AI_COMPLETE |
|--------|-----------|-------------|
| Slips extracted | 39 | 75 |
| Line items | 9 | 271 |
| Page numbers | None | Yes |

## Prerequisites

- Python 3.9+ with `pypdfium2` (`pip install pypdfium2`)
- Snowflake account with Cortex AI functions enabled
- A warehouse (the pipeline uses `COMPUTE_WH` — change in `05_automation.sql` if yours differs)
- `snow` CLI installed for file uploads and Streamlit deployment
- ACCOUNTADMIN or a role with CREATE DATABASE, CREATE STAGE, and Cortex AI privileges

## Setup

### 1. Run the SQL scripts to create infrastructure

```bash
snow sql -f sql/01_infrastructure.sql -c <connection>
snow sql -f sql/06_purchase_orders.sql -c <connection>
snow sql -f sql/07_reconciliation_view.sql -c <connection>
snow sql -f sql/05_automation.sql -c <connection>
```

### 2. Split the PDFs locally

```bash
pip install pypdfium2

# First run: use local heuristic mode (no Snowflake mapping needed)
python3 split_packing_slips.py \
  --input SamplePackingSlips/ \
  --output SplitSlips/ \
  --ocr

# Or with a Snowflake mapping CSV (more accurate, see "Generating the mapping" below)
python3 split_packing_slips.py \
  --input SamplePackingSlips/ \
  --output SplitSlips/ \
  --mapping slip_mapping.csv
```

This creates one PDF per packing slip in `SplitSlips/` and a `split_manifest.csv`
with the source file, page range, PO number, and supplier for each slip.

**Generating the mapping from Snowflake** (after the first batch has been
processed through the pipeline on `@RAW_DOCS`):

```sql
SELECT e.FILE_NAME, f.INDEX AS SLIP_IDX,
    f.VALUE:approximate_page::INT AS START_PAGE,
    COALESCE(LEAD(f.VALUE:approximate_page::INT)
        OVER (PARTITION BY e.FILE_NAME ORDER BY f.INDEX),
        p.PAGE_COUNT + 1) AS NEXT_SLIP_PAGE,
    p.PAGE_COUNT,
    f.VALUE:po_number::VARCHAR AS PO_NUMBER,
    f.VALUE:supplier_name::VARCHAR AS SUPPLIER_NAME
FROM AI_COMPLETE_EXTRACTIONS e
CROSS JOIN LATERAL FLATTEN(input => e.PARSED_JSON) f
LEFT JOIN PARSED_DOCUMENTS p ON e.FILE_NAME = p.FILE_NAME
ORDER BY e.FILE_NAME, f.INDEX;
```

### 3. Upload split files to Snowflake

```bash
snow sql -c <connection> -q \
  "PUT file:///path/to/SplitSlips/*.pdf @PACKING_SLIP_PROCESSING.PACKING_SLIPS.SPLIT_SLIPS AUTO_COMPRESS=FALSE OVERWRITE=TRUE"

snow sql -c <connection> -q \
  "ALTER STAGE PACKING_SLIP_PROCESSING.PACKING_SLIPS.SPLIT_SLIPS REFRESH"
```

### 4. Run the extraction pipeline

```bash
snow sql -f sql/02_parse_documents.sql -c <connection>
snow sql -f sql/03_extract_with_ai_complete.sql -c <connection>
snow sql -f sql/04_flatten_and_score.sql -c <connection>
```

### 5. Deploy the Streamlit app

```bash
snow streamlit deploy --replace --prune -c <connection>
```

### 6. Enable automated processing (optional)

```sql
ALTER TASK PACKING_SLIP_PROCESSING.PACKING_SLIPS.PROCESS_PACKING_SLIPS_TASK RESUME;
```

## Using the Review App

The app has two tabs:

### Review Queue

- **Left side**: Rendered PDF of the individual packing slip (one file per slip,
  no page sync issues). Uses `PDF_PAGE_TO_PNG` UDF with pypdfium2.
- **Right side**: Editable header fields (PO, supplier, dates, carrier, etc.)
  and editable line items (Part#, Description, Qty Ordered, Qty Shipped, UOM).
  Each line item row has an X checkbox for deletion. "+ Add Line Item" button
  to add new rows.
- **Actions**: Approve, Save Corrections, or Reject at the bottom of the form.
- **Navigation**: Prev/Next buttons. Status filter defaults to PENDING.

### Dashboard

- Top metrics: PDFs processed, slips extracted, line items, pending review, approved
- Review status breakdown with confidence stats
- Confidence score distribution
- Top suppliers by volume (slip + line item counts)
- Documents processed (per-PDF breakdown)
- Line item field completeness (% with part number, description, qty)
- Header field completeness (% with PO, supplier, date, carrier, etc.)
- Extraction error log

## Confidence Scoring

Each slip gets a score from 0 to 1:

| Factor | Weight | Logic |
|--------|--------|-------|
| Field completeness | 0.50 | Proportion of 6 key fields populated |
| PO format valid | 0.20 | PO number is alphanumeric |
| Date valid | 0.15 | Shipment date parses as a real date |
| Has line items | 0.15 | At least one line item with a part number |

Thresholds (configurable in `PIPELINE_CONFIG`):

| Status | Condition |
|--------|-----------|
| AUTO_APPROVED | score >= 0.85 |
| NEEDS_REVIEW | score < 0.60 |
| PENDING | 0.60 <= score < 0.85 |
| SPOT_CHECK | 5% random sample of AUTO_APPROVED |

## File Inventory

```
packing-slip-processing/
  README.md                              -- this file
  snowflake.yml                          -- Streamlit deployment config
  streamlit_app.py                       -- Streamlit HITL review app
  split_packing_slips.py                 -- Local PDF splitter script
  slip_mapping.csv                       -- AI-detected page-to-slip mapping
  generate_sample_pdfs.py                -- generates synthetic packing slip PDFs
  SamplePackingSlips/                    -- sample multi-page PDFs (3 bundles)
  SplitSlips/                            -- pre-split individual slip PDFs (15 files)
    split_manifest.csv                   -- manifest of all split files
  sql/
    01_infrastructure.sql                -- DB, schema, stages, tables, UDFs
    02_parse_documents.sql               -- AI_PARSE_DOCUMENT batch
    03_extract_with_ai_complete.sql      -- AI_COMPLETE extraction
    04_flatten_and_score.sql             -- Flatten JSON + confidence scoring
    05_automation.sql                    -- Stream, stored procedure, task
    06_purchase_orders.sql               -- Mock PO data
    07_reconciliation_view.sql           -- Reconciliation view DDL
  presentations/
    packing-slip-automation.html         -- slide deck
```

## Snowflake Objects

| Object | Type | Purpose |
|--------|------|---------|
| `RAW_DOCS` | Stage | Original multi-page PDF storage |
| `SPLIT_SLIPS` | Stage | Pre-split individual slip PDFs (one file per slip) |
| `NEW_DOCUMENTS_STREAM` | Stream | Detects new files in @SPLIT_SLIPS |
| `PROCESS_NEW_DOCUMENTS()` | Procedure | End-to-end pipeline per file |
| `PROCESS_PACKING_SLIPS_TASK` | Task | Triggers procedure on new files |
| `PDF_PAGE_TO_PNG()` | UDF | Renders PDF page as PNG for Streamlit |
| `PARSED_DOCUMENTS` | Table | Raw OCR text from AI_PARSE_DOCUMENT |
| `AI_COMPLETE_EXTRACTIONS` | Table | Raw AI_COMPLETE JSON responses |
| `PACKING_SLIP_HEADERS` | Table | Flattened header fields per slip |
| `PACKING_SLIP_LINE_ITEMS` | Table | Flattened line items per slip |
| `PURCHASE_ORDERS` | Table | PO master data (replace with ERP feed) |
| `PO_LINE_ITEMS` | Table | PO line items (replace with ERP feed) |
| `PIPELINE_CONFIG` | Table | Configurable scoring thresholds |
| `EXTRACTION_ERRORS` | Table | Pipeline error log |
| `RECONCILIATION_VIEW` | View | PO mismatch detection |

## Known Limitations

1. **Rotated/sideways pages**: Warehouse order acknowledgements with 90-degree
   rotated text extract poorly. Preprocessing to auto-rotate would improve results.

2. **SiS Streamlit version**: The Streamlit-in-Snowflake runtime runs an older
   Streamlit version. The app avoids newer APIs (`st.rerun`, `use_container_width`,
   `hide_index`, `type="primary"`, `st.data_editor`). PDF display uses a Python
   UDF (`PDF_PAGE_TO_PNG`) to render pages as images via `st.image`. Line item
   editing uses individual `st.text_input` fields per cell.

3. **Local splitter dependency**: The `split_packing_slips.py` script requires
   `pypdfium2`. For the most accurate slip boundary detection, run the initial
   batch through the Snowflake AI pipeline first to generate the mapping CSV,
   then use it for splitting.
