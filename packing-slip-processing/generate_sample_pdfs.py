#!/usr/bin/env python3
"""Generate synthetic packing slip PDFs for the enablement lab."""

import csv
import os
import random
import shutil
import string
from fpdf import FPDF

random.seed(42)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
BUNDLE_DIR = os.path.join(BASE_DIR, "SamplePackingSlips")
SPLIT_DIR = os.path.join(BASE_DIR, "SplitSlips")

SHIP_TO = ["Summit Distribution Center", "1200 Commerce Blvd", "Springfield, IL 62701"]
BILL_TO = ["Summit Industries HQ", "500 Industrial Pkwy", "Springfield, IL 62704"]

SUPPLIERS = {
    "Precision Coating and Finishing": {
        "address": ["8400 Metal Works Dr", "Peoria, IL 61615"],
        "parts": [
            ("PCF-ZN-100", "Zinc plating service  - small batch", "EA"),
            ("PCF-ANO-205", "Anodized aluminum panel 12x24", "EA"),
            ("PCF-PWD-310", "Powder coat finish  - RAL 9005 black", "SQ FT"),
            ("PCF-CHR-050", "Chrome plating  - shaft assembly", "EA"),
            ("PCF-EPX-420", "Epoxy primer coat  - structural steel", "GAL"),
            ("PCF-NKL-115", "Electroless nickel plating  - connector pins", "LOT"),
        ],
    },
    "Apex Electronics and Controls": {
        "address": ["2200 Circuit Ave, Suite 100", "Champaign, IL 61820"],
        "parts": [
            ("AEC-CB-7100", "Control board assembly Rev C", "EA"),
            ("AEC-PS-240V", "Power supply 240V/10A", "EA"),
            ("AEC-PWR-14G", "Power cord 14AWG 6ft NEMA 5-15P", "EA"),
            ("AEC-SEN-T03", "Temperature sensor probe K-type", "EA"),
            ("AEC-RLY-DC24", "Relay module 24VDC 4-channel", "EA"),
            ("AEC-HRN-016", "Wire harness assembly 16-pin", "EA"),
        ],
    },
    "Central Supply Co": {
        "address": ["700 Warehouse Row", "Decatur, IL 62526"],
        "parts": [
            ("CS-GLV-LG", "Nitrile gloves large  - box/100", "BX"),
            ("CS-TAG-3X5", "Shipping tags 3x5 manila  - pack/500", "PK"),
            ("CS-WRAP-18", "Stretch wrap 18in x 1500ft", "RL"),
            ("CS-TAPE-2CL", "Packing tape 2in clear  - case/36", "CS"),
            ("CS-PAD-24", "Foam padding sheets 24x36", "EA"),
            ("CS-LABEL-4X6", "Thermal labels 4x6  - roll/500", "RL"),
        ],
    },
    "Eagle Transfer and Logistics": {
        "address": ["1515 Freight Terminal Rd", "East St. Louis, IL 62201"],
        "parts": [
            ("ETL-PLT-48", "Standard pallet 48x40 GMA", "EA"),
            ("ETL-CRT-LG", "Wooden crate  - large 48x36x30", "EA"),
            ("ETL-DRUM-55", "Steel drum 55 gallon closed-top", "EA"),
            ("ETL-STRP-HVY", "Heavy-duty banding strap 3/4in", "RL"),
            ("ETL-DNSTY-BLK", "Dunnage blocks 4x4x12 recycled", "EA"),
            ("ETL-BLK-FOAM", "Foam block insert custom cut", "EA"),
        ],
    },
    "Heritage Woodworks": {
        "address": ["340 Mill Creek Rd", "Galesburg, IL 61401"],
        "parts": [
            ("HW-OAK-3Q", "Red oak board 3/4 x 6 x 96", "EA"),
            ("HW-PLY-BB", "Baltic birch plywood 1/2in 4x8", "SHT"),
            ("HW-MLD-CR08", "Crown molding profile 8ft oak", "EA"),
            ("HW-DWL-38", "Hardwood dowel 3/8 x 36in", "EA"),
            ("HW-PNL-WNT", "Walnut panel glue-up 18x36", "EA"),
            ("HW-TRIM-BS4", "Baseboard trim 4-1/4 poplar 12ft", "EA"),
        ],
    },
    "ProLine Extrusions, Inc.": {
        "address": ["9000 Aluminum Way", "Rockford, IL 61108"],
        "parts": [
            ("PLN-EXT-A22", "Aluminum extrusion T-slot 22mm 6ft", "EA"),
            ("PLN-ANG-1X1", "Aluminum angle 1x1x1/8 8ft", "EA"),
            ("PLN-CHN-C4", "C-channel extrusion 4in 10ft", "EA"),
            ("PLN-FLAT-2", "Flat bar 6061-T6 2x1/4 8ft", "EA"),
            ("PLN-TB-RND2", "Round tube 2in OD 0.065 wall 12ft", "EA"),
            ("PLN-HSS-3X3", "Square tube 3x3x1/4 20ft", "EA"),
        ],
    },
    "Atlas Coatings Inc": {
        "address": ["455 Paint Factory Ln", "Bloomington, IL 61701"],
        "parts": [
            ("AC-PRM-GRY5", "Primer gray #5  - 5 gallon pail", "EA"),
            ("AC-ENAM-WHT", "Industrial enamel white gloss 1gal", "EA"),
            ("AC-POLY-CLR", "Polyurethane clear satin 1gal", "EA"),
            ("AC-RST-RED", "Rust inhibitor red oxide 5gal", "EA"),
            ("AC-THINNER-1", "Lacquer thinner 1 gallon", "EA"),
            ("AC-SPRAY-BLK", "Aerosol spray paint flat black 12oz", "EA"),
        ],
    },
    "BoltSource": {
        "address": ["120 Fastener Pkwy", "Joliet, IL 60435"],
        "parts": [
            ("BC-HX-0516", "Hex bolt 5/16-18 x 1-1/2 GR5 zinc", "BX"),
            ("BC-NT-0516", "Hex nut 5/16-18 zinc  - box/100", "BX"),
            ("BC-WS-516F", "Flat washer 5/16 zinc  - box/100", "BX"),
            ("BC-SCR-M6", "Socket head cap screw M6x25 SS", "BX"),
            ("BC-ANC-38", "Wedge anchor 3/8 x 3 zinc", "BX"),
            ("72B-3100", "Carriage bolt 3/8-16 x 3 GR5 zinc", "BX"),
        ],
    },
    "Nova Systems LLC": {
        "address": ["3050 Innovation Ct", "Normal, IL 61761"],
        "parts": [
            ("NS-VLV-BV2", "Ball valve 2in brass NPT", "EA"),
            ("NS-PMP-C110", "Centrifugal pump 1HP 110V", "EA"),
            ("NS-FLT-HEPA", "HEPA filter cartridge 12x24x6", "EA"),
            ("NS-MNF-ASY", "Manifold assembly 4-port 1/2NPT", "EA"),
            ("NS-GAG-PSI", "Pressure gauge 0-200 PSI 4in dial", "EA"),
            ("NS-ACT-PNE", "Pneumatic actuator double-acting", "EA"),
        ],
    },
    "CoreLink Partners": {
        "address": ["880 Packaging Blvd", "Springfield, IL 62702"],
        "parts": [
            ("CLP-BX-12C", "Corrugated box 12x12x12  - bundle/25", "BDL"),
            ("CLP-BX-24L", "Corrugated box 24x18x12  - bundle/15", "BDL"),
            ("CLP-FILL-PN", "Packing peanuts 14 cu ft bag", "BAG"),
            ("CLP-BUBBLE-24", "Bubble wrap 24in x 250ft roll", "RL"),
            ("CLP-MLER-10", "Poly mailer 10x13  - pack/100", "PK"),
            ("CLP-INSERT-A", "Custom foam insert  - type A", "EA"),
        ],
    },
}

CARRIERS = ["FedEx Freight", "UPS Ground", "USPS Priority", "YRC Freight", "Old Dominion", "Conway Freight"]
DOC_TYPES = ["PACKING SLIP", "BILL OF LADING", "SHIPMENT NOTICE"]


def random_tracking():
    prefix = random.choice(["1Z", "TRK", "PRO", ""])
    body = "".join(random.choices(string.ascii_uppercase + string.digits, k=random.randint(12, 18)))
    return prefix + body


def random_po():
    return f"PSN{random.randint(100000, 999999)}"


def random_date():
    day = random.randint(1, 31)
    return f"07/{day:02d}/2026"


def pick_supplier():
    name = random.choice(list(SUPPLIERS.keys()))
    return name, SUPPLIERS[name]


def pick_line_items(supplier_data, count):
    parts = supplier_data["parts"]
    selected = random.sample(parts, min(count, len(parts)))
    items = []
    for part_no, desc, uom in selected:
        qty_ordered = random.randint(1, 500)
        qty_shipped = qty_ordered if random.random() < 0.8 else random.randint(1, qty_ordered)
        items.append((part_no, desc, qty_ordered, qty_shipped, uom))
    return items


class PackingSlipPDF(FPDF):
    def __init__(self):
        super().__init__()
        self.set_auto_page_break(auto=False)


def draw_packing_slip(pdf, slip_info, page_label=None):
    pdf.add_page()
    pw = pdf.w - 20  # usable width with 10mm margins

    # outer border
    pdf.rect(10, 10, pw, pdf.h - 20)

    # header bar
    pdf.set_fill_color(30, 30, 80)
    pdf.rect(10, 10, pw, 16, "F")
    pdf.set_font("Helvetica", "B", 18)
    pdf.set_text_color(255, 255, 255)
    pdf.set_xy(14, 12)
    pdf.cell(pw - 8, 12, slip_info["doc_type"], align="L")

    # doc number / date on right
    pdf.set_font("Helvetica", "", 10)
    pdf.set_xy(14, 12)
    pdf.cell(pw - 8, 12, f"Date: {slip_info['date']}", align="R")

    pdf.set_text_color(0, 0, 0)
    y = 30

    # supplier / ship-to / bill-to row
    col_w = pw / 3
    for col_idx, (label, lines) in enumerate([
        ("FROM / SUPPLIER", [slip_info["supplier_name"]] + slip_info["supplier_addr"]),
        ("SHIP TO", SHIP_TO),
        ("BILL TO", BILL_TO),
    ]):
        x = 10 + col_idx * col_w
        pdf.set_font("Helvetica", "B", 8)
        pdf.set_xy(x + 2, y)
        pdf.cell(col_w - 4, 5, label)
        pdf.set_font("Helvetica", "", 9)
        for i, line in enumerate(lines):
            pdf.set_xy(x + 2, y + 6 + i * 4.5)
            pdf.cell(col_w - 4, 4.5, line)
        # vertical separator
        if col_idx < 2:
            pdf.line(x + col_w, y, x + col_w, y + 28)

    # box around address block
    pdf.rect(10, y - 1, pw, 30)
    y += 32

    # reference fields row
    ref_fields = [
        ("PO Number", slip_info["po"]),
        ("Carrier", slip_info["carrier"]),
        ("Tracking #", slip_info["tracking"]),
    ]
    ref_w = pw / len(ref_fields)
    pdf.rect(10, y, pw, 12)
    for i, (lbl, val) in enumerate(ref_fields):
        x = 10 + i * ref_w
        pdf.set_font("Helvetica", "B", 8)
        pdf.set_xy(x + 2, y + 1)
        pdf.cell(ref_w - 4, 4, lbl)
        pdf.set_font("Helvetica", "", 9)
        pdf.set_xy(x + 2, y + 6)
        pdf.cell(ref_w - 4, 5, val)
        if i < len(ref_fields) - 1:
            pdf.line(x + ref_w, y, x + ref_w, y + 12)
    y += 15

    # line items table
    col_widths = [28, 76, 22, 22, 22]  # part, desc, qty_ord, qty_ship, uom
    headers = ["Part Number", "Description", "Qty Ordered", "Qty Shipped", "UOM"]

    # header row
    pdf.set_fill_color(220, 220, 220)
    pdf.set_font("Helvetica", "B", 8)
    x = 10 + (pw - sum(col_widths)) / 2
    start_x = x
    for i, (hdr, w) in enumerate(zip(headers, col_widths)):
        pdf.set_xy(x, y)
        pdf.cell(w, 7, hdr, border=1, fill=True, align="C")
        x += w
    y += 7

    # data rows
    pdf.set_font("Helvetica", "", 8)
    items = slip_info["items"]
    for part_no, desc, qty_ord, qty_ship, uom in items:
        x = start_x
        row_data = [part_no, desc, str(qty_ord), str(qty_ship), uom]
        aligns = ["L", "L", "C", "C", "C"]
        for val, w, a in zip(row_data, col_widths, aligns):
            pdf.set_xy(x, y)
            pdf.cell(w, 6, val, border=1, align=a)
            x += w
        y += 6

    # fill remaining table rows to look uniform (empty rows)
    empty_rows = max(0, 6 - len(items))
    for _ in range(empty_rows):
        x = start_x
        for w in col_widths:
            pdf.set_xy(x, y)
            pdf.cell(w, 6, "", border=1)
            x += w
        y += 6

    # totals row
    pdf.set_font("Helvetica", "B", 8)
    x = start_x
    pdf.set_xy(x, y)
    pdf.cell(col_widths[0] + col_widths[1], 7, "TOTAL ITEMS", border=1, align="R")
    x += col_widths[0] + col_widths[1]
    total_ord = sum(it[2] for it in items)
    total_ship = sum(it[3] for it in items)
    pdf.set_xy(x, y)
    pdf.cell(col_widths[2], 7, str(total_ord), border=1, align="C")
    x += col_widths[2]
    pdf.set_xy(x, y)
    pdf.cell(col_widths[3], 7, str(total_ship), border=1, align="C")
    x += col_widths[3]
    pdf.set_xy(x, y)
    pdf.cell(col_widths[4], 7, "", border=1)
    y += 10

    # notes / footer
    pdf.set_font("Helvetica", "", 8)
    pdf.set_xy(12, y)
    notes = random.choice([
        "Please inspect goods upon receipt and report discrepancies within 48 hours.",
        "All items subject to standard terms and conditions.",
        "Receiver must verify quantities before signing.",
        "Contact supplier for returns authorization within 30 days.",
        "Partial shipment  - remaining items to follow.",
    ])
    pdf.multi_cell(pw - 4, 4, f"Notes: {notes}")
    y += 14

    # signature line
    pdf.line(12, y + 10, 80, y + 10)
    pdf.set_xy(12, y + 11)
    pdf.cell(68, 5, "Received By (signature)")
    pdf.line(100, y + 10, 170, y + 10)
    pdf.set_xy(100, y + 11)
    pdf.cell(70, 5, "Date")

    # page label if multi-page slip
    if page_label:
        pdf.set_font("Helvetica", "I", 7)
        pdf.set_xy(10, pdf.h - 14)
        pdf.cell(pw, 4, page_label, align="R")

    return slip_info


def generate_slip_info(force_supplier=None):
    if force_supplier:
        name = force_supplier
        data = SUPPLIERS[name]
    else:
        name, data = pick_supplier()
    num_items = random.randint(2, 6)
    return {
        "doc_type": random.choice(DOC_TYPES),
        "supplier_name": name,
        "supplier_addr": data["address"],
        "po": random_po(),
        "date": random_date(),
        "carrier": random.choice(CARRIERS),
        "tracking": random_tracking(),
        "items": pick_line_items(data, num_items),
    }


def make_bundle(bundle_name, slip_specs):
    """slip_specs: list of dicts with 'pages' (int) key and optional 'supplier'."""
    bundle_pdf = PackingSlipPDF()
    individual_slips = []

    for slip_idx, spec in enumerate(slip_specs):
        pages = spec.get("pages", 1)
        info = generate_slip_info(force_supplier=spec.get("supplier"))
        start_page = bundle_pdf.page + 1  # next page number (1-indexed)

        if pages == 1:
            draw_packing_slip(bundle_pdf, info)
        else:
            # split items across pages
            all_items = info["items"]
            # ensure enough items for multi-page
            while len(all_items) < pages * 2:
                extra = pick_line_items(SUPPLIERS[info["supplier_name"]], 3)
                all_items.extend(extra)
            chunk_size = max(2, len(all_items) // pages)
            for pg in range(pages):
                page_items = all_items[pg * chunk_size : (pg + 1) * chunk_size]
                if pg == pages - 1:
                    page_items = all_items[pg * chunk_size :]
                page_info = dict(info)
                page_info["items"] = page_items
                label = f"Page {pg + 1} of {pages}" if pages > 1 else None
                draw_packing_slip(bundle_pdf, page_info, page_label=label)

        end_page = bundle_pdf.page
        individual_slips.append({
            "info": info,
            "start_page": start_page,
            "end_page": end_page,
            "num_pages": end_page - start_page + 1,
            "slip_idx": slip_idx + 1,
        })

    bundle_path = os.path.join(BUNDLE_DIR, f"{bundle_name}.pdf")
    bundle_pdf.output(bundle_path)
    print(f"  Created bundle: {bundle_path} ({bundle_pdf.page} pages)")
    return individual_slips


def save_individual_slips(bundle_name, slips):
    """Re-generate each slip as a standalone PDF and return manifest rows."""
    manifest_rows = []
    for slip in slips:
        info = slip["info"]
        slip_num = slip["slip_idx"]
        num_pages = slip["num_pages"]
        filename = f"{bundle_name}_slip_{slip_num:03d}.pdf"
        filepath = os.path.join(SPLIT_DIR, filename)

        slip_pdf = PackingSlipPDF()
        if num_pages == 1:
            draw_packing_slip(slip_pdf, info)
        else:
            all_items = info["items"]
            chunk_size = max(2, len(all_items) // num_pages)
            for pg in range(num_pages):
                page_items = all_items[pg * chunk_size : (pg + 1) * chunk_size]
                if pg == num_pages - 1:
                    page_items = all_items[pg * chunk_size :]
                page_info = dict(info)
                page_info["items"] = page_items
                label = f"Page {pg + 1} of {num_pages}" if num_pages > 1 else None
                draw_packing_slip(slip_pdf, page_info, page_label=label)
        slip_pdf.output(filepath)

        manifest_rows.append({
            "source": f"{bundle_name}.pdf",
            "slip_num": slip_num,
            "start_page": slip["start_page"],
            "end_page": slip["end_page"],
            "num_pages": num_pages,
            "output_file": filename,
            "po_number": info["po"],
            "supplier": info["supplier_name"],
        })
    return manifest_rows


def main():
    # Clean old files
    print("Cleaning old files...")
    for f in os.listdir(BUNDLE_DIR):
        os.remove(os.path.join(BUNDLE_DIR, f))
    for f in os.listdir(SPLIT_DIR):
        fp = os.path.join(SPLIT_DIR, f)
        if f.endswith(".pdf"):
            os.remove(fp)

    supplier_names = list(SUPPLIERS.keys())

    # Bundle 1: 5 single-page slips
    print("Generating sample_batch_001...")
    b1_specs = [{"pages": 1, "supplier": supplier_names[i]} for i in range(5)]
    b1_slips = make_bundle("sample_batch_001", b1_specs)

    # Bundle 2: 7 slips, one is 2 pages = 8 pages total
    print("Generating sample_batch_002...")
    b2_specs = []
    two_page_idx = random.randint(0, 6)
    for i in range(7):
        sup = supplier_names[(5 + i) % len(supplier_names)]
        if i == two_page_idx:
            b2_specs.append({"pages": 2, "supplier": sup})
        else:
            b2_specs.append({"pages": 1, "supplier": sup})
    b2_slips = make_bundle("sample_batch_002", b2_specs)

    # Bundle 3: 3 single-page slips
    print("Generating sample_batch_003...")
    b3_specs = [{"pages": 1, "supplier": supplier_names[(8 + i) % len(supplier_names)]} for i in range(3)]
    b3_slips = make_bundle("sample_batch_003", b3_specs)

    # Generate individual split PDFs and manifest
    print("Generating individual slip PDFs...")
    all_manifest = []
    for bundle_name, slips in [
        ("sample_batch_001", b1_slips),
        ("sample_batch_002", b2_slips),
        ("sample_batch_003", b3_slips),
    ]:
        rows = save_individual_slips(bundle_name, slips)
        all_manifest.extend(rows)

    # Write manifest CSV
    manifest_path = os.path.join(SPLIT_DIR, "split_manifest.csv")
    with open(manifest_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "source", "slip_num", "start_page", "end_page", "num_pages",
            "output_file", "po_number", "supplier",
        ])
        writer.writeheader()
        writer.writerows(all_manifest)
    print(f"  Wrote manifest: {manifest_path} ({len(all_manifest)} slips)")

    print("\nDone! Generated:")
    print(f"  3 bundle PDFs in {BUNDLE_DIR}")
    print(f"  {len(all_manifest)} individual slip PDFs in {SPLIT_DIR}")
    print(f"  split_manifest.csv with {len(all_manifest)} rows")


if __name__ == "__main__":
    main()
