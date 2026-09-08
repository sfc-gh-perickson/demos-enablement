#!/usr/bin/env python3
"""
split_packing_slips.py

Splits multi-page packing slip PDFs into individual per-slip PDF files.

Two modes:
  1. With a mapping CSV from Snowflake (--mapping): uses AI-detected slip boundaries
  2. Without mapping (--ocr): uses local text extraction + pattern matching to detect boundaries

Usage:
  # Mode 1: Using Snowflake mapping (recommended for accuracy)
  # First export the mapping from Snowflake:
  #   SELECT FILE_NAME, SLIP_IDX, START_PAGE, PO_NUMBER, SUPPLIER_NAME
  #   FROM ... (see README for full query)
  # Then run:
  python3 split_packing_slips.py --input SamplePackingSlips/ --output SplitSlips/ --mapping slip_mapping.csv

  # Mode 2: Local heuristic (no Snowflake needed)
  python3 split_packing_slips.py --input SamplePackingSlips/ --output SplitSlips/ --ocr
"""

import argparse
import csv
import io
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

import pypdfium2 as pdfium


# Patterns that indicate the START of a new packing slip page
NEW_SLIP_PATTERNS = [
    r'Packing\s+Slip',
    r'PACKING\s+SLIP',
    r'Shipment\s*\n.*Shipment\s+Number',
    r'Bill\s+of\s+Lading',
    r'BILL\s+OF\s+LADING',
    r'STRAIGHT\s+BILL\s+OF\s+LADING',
    r'ASN\s+Report',
    r'WAREHOUSE\s+ORDER',
    r'Warehouse\s+Order',
    r'PURCHASE\s+ORDER\s*\n',
    r'P\.O\.\s+Number',
    r'Ship\s*-?\s*To[:\s]',
    # Supplier-specific headers
    r'PRECISION\s+COATING',
    r'Atlas\s+Coatings',
    r'ProLine',
    r'CoreLink\s+Partners',
    r'Packing\s+Slip\s+Report',
    r'Nova\s+Systems',
    r'Premier\s+Lubricants',
    r'Central\s+Supply',
    r'Eagle\s+Transfer',
    r'Heritage\s+Woodworks',
    r'Apex\s+Electronics',
    r'BoltSource',
    r'SafeShip',
    r'National\s+Industrial',
    r'Delta\s+Electronics',
]


def extract_text_from_page(pdf, page_num):
    """Extract text from a PDF page using pypdfium2's built-in text extraction."""
    page = pdf[page_num]
    textpage = page.get_textpage()
    text = textpage.get_text_range()
    textpage.close()
    page.close()
    return text


def is_new_slip_page(text):
    """Check if a page's text indicates the start of a new packing slip."""
    if not text or len(text.strip()) < 20:
        return True  # Nearly blank page = treat as new slip boundary
    for pattern in NEW_SLIP_PATTERNS:
        if re.search(pattern, text, re.IGNORECASE):
            return True
    return False


def detect_slip_boundaries_local(pdf_path):
    """Detect slip boundaries using local text extraction + pattern matching."""
    pdf = pdfium.PdfDocument(pdf_path)
    n_pages = len(pdf)
    boundaries = []  # list of (start_page, end_page) tuples, 1-based

    current_start = 1
    for i in range(n_pages):
        text = extract_text_from_page(pdf, i)
        page_num = i + 1  # 1-based

        if page_num == 1:
            current_start = 1
            continue

        if is_new_slip_page(text):
            boundaries.append((current_start, page_num - 1))
            current_start = page_num

    # Last slip
    boundaries.append((current_start, n_pages))
    pdf.close()
    return boundaries


def load_mapping(mapping_path):
    """Load slip mapping CSV exported from Snowflake."""
    mapping = defaultdict(list)
    with open(mapping_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            fname = row['FILE_NAME']
            start = int(row['START_PAGE'])
            next_page = int(row['NEXT_SLIP_PAGE']) if row.get('NEXT_SLIP_PAGE') else None
            page_count = int(row['PAGE_COUNT']) if row.get('PAGE_COUNT') else None
            po = row.get('PO_NUMBER', '')
            supplier = row.get('SUPPLIER_NAME', '')
            mapping[fname].append({
                'start': start,
                'next': next_page,
                'page_count': page_count,
                'po': po,
                'supplier': supplier,
            })
    # Sort each file's slips by start page and compute end pages
    result = {}
    for fname, slips in mapping.items():
        slips.sort(key=lambda x: x['start'])
        boundaries = []
        for i, s in enumerate(slips):
            start = s['start']
            if s['next']:
                end = s['next'] - 1
            elif i + 1 < len(slips):
                end = slips[i + 1]['start'] - 1
            else:
                end = s.get('page_count') or start
            boundaries.append((start, end, s['po'], s['supplier']))
        result[fname] = boundaries
    return result


def split_pdf(pdf_path, boundaries, output_dir, source_name):
    """Split a PDF into individual slip files based on page boundaries."""
    pdf = pdfium.PdfDocument(pdf_path)
    files_created = []

    for i, boundary in enumerate(boundaries):
        if len(boundary) == 4:
            start, end, po, supplier = boundary
        else:
            start, end = boundary
            po, supplier = '', ''

        # Clamp to actual page count
        start_idx = max(0, start - 1)  # convert to 0-based
        end_idx = min(len(pdf) - 1, end - 1)
        page_indices = list(range(start_idx, end_idx + 1))

        if not page_indices:
            continue

        new_pdf = pdfium.PdfDocument.new()
        new_pdf.import_pages(pdf, page_indices)

        base = source_name.replace('.pdf', '').replace('.PDF', '')
        slip_num = i + 1
        out_name = f"{base}_slip_{slip_num:03d}.pdf"
        out_path = os.path.join(output_dir, out_name)

        with open(out_path, 'wb') as f:
            new_pdf.save(f)
        new_pdf.close()

        files_created.append({
            'source': source_name,
            'slip_num': slip_num,
            'start_page': start,
            'end_page': end,
            'num_pages': len(page_indices),
            'output_file': out_name,
            'po_number': po,
            'supplier': supplier,
        })

    pdf.close()
    return files_created


def main():
    parser = argparse.ArgumentParser(description='Split multi-page packing slip PDFs into individual slip files.')
    parser.add_argument('--input', '-i', required=True, help='Input directory containing PDF files')
    parser.add_argument('--output', '-o', required=True, help='Output directory for split PDF files')
    parser.add_argument('--mapping', '-m', help='CSV file with slip-to-page mapping from Snowflake')
    parser.add_argument('--ocr', action='store_true', help='Use local text extraction for boundary detection (no Snowflake needed)')
    parser.add_argument('--manifest', default='split_manifest.csv', help='Output manifest CSV path')
    args = parser.parse_args()

    if not args.mapping and not args.ocr:
        print("Error: specify either --mapping <csv> or --ocr")
        print("  --mapping: use Snowflake AI-detected boundaries (most accurate)")
        print("  --ocr: use local text pattern matching (no Snowflake needed)")
        sys.exit(1)

    input_dir = Path(args.input)
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Load mapping if provided
    sf_mapping = {}
    if args.mapping:
        sf_mapping = load_mapping(args.mapping)
        print(f"Loaded mapping for {len(sf_mapping)} files from {args.mapping}")

    # Find all PDFs
    pdfs = sorted(input_dir.glob('*.pdf')) + sorted(input_dir.glob('*.PDF'))
    print(f"Found {len(pdfs)} PDF files in {input_dir}")

    all_results = []

    for pdf_path in pdfs:
        fname = pdf_path.name
        pdf = pdfium.PdfDocument(str(pdf_path))
        n_pages = len(pdf)
        pdf.close()

        print(f"\n  {fname}: {n_pages} pages")

        if n_pages == 1:
            # Single page = single slip, just copy
            boundaries = [(1, 1, '', '')]
        elif fname in sf_mapping:
            # Use Snowflake mapping
            boundaries = sf_mapping[fname]
            print(f"    Using Snowflake mapping: {len(boundaries)} slips detected")
        elif args.ocr:
            # Use local detection
            raw_boundaries = detect_slip_boundaries_local(str(pdf_path))
            boundaries = [(s, e, '', '') for s, e in raw_boundaries]
            print(f"    Using local detection: {len(boundaries)} slips detected")
        else:
            print(f"    WARNING: No mapping for {fname} and --ocr not set. Skipping.")
            continue

        results = split_pdf(str(pdf_path), boundaries, str(output_dir), fname)
        all_results.extend(results)
        print(f"    Created {len(results)} slip files")

    # Write manifest
    manifest_path = os.path.join(str(output_dir), args.manifest)
    with open(manifest_path, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=[
            'source', 'slip_num', 'start_page', 'end_page', 'num_pages',
            'output_file', 'po_number', 'supplier'
        ])
        writer.writeheader()
        writer.writerows(all_results)

    print(f"\nDone. Created {len(all_results)} slip files in {output_dir}")
    print(f"Manifest written to {manifest_path}")


if __name__ == '__main__':
    main()
