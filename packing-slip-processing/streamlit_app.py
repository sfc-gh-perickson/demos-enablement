import streamlit as st
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="Packing Slip Review", layout="wide")
session = get_active_session()

FQ = "PACKING_SLIP_PROCESSING.PACKING_SLIPS"
SLIP_STAGE = f"@{FQ}.SPLIT_SLIPS"

def qry(sql):
    return session.sql(sql).to_pandas()

def exe(sql):
    session.sql(sql).collect()

def esc(v):
    return str(v).replace("'", "''")

if "idx" not in st.session_state:
    st.session_state.idx = 0
if "li_rows" not in st.session_state:
    st.session_state.li_rows = []
if "li_loaded_for" not in st.session_state:
    st.session_state.li_loaded_for = -1

tab1, tab2 = st.tabs(["Review Queue", "Dashboard"])

# ============================================================
# TAB 1: REVIEW QUEUE
# ============================================================
with tab1:
    st.header("Packing Slip Review")

    status_filter = st.selectbox("Status filter",
        ["PENDING", "AUTO_APPROVED", "ALL", "APPROVED", "CORRECTED", "REJECTED"])

    where = "" if status_filter == "ALL" else f"WHERE h.REVIEW_STATUS = '{status_filter}'"
    queue = qry(f"""
        SELECT h.HEADER_ID, h.PO_NUMBER, h.SUPPLIER_NAME, h.SHIPMENT_DATE,
               h.CONFIDENCE_SCORE, h.REVIEW_STATUS, h.FILE_NAME, h.PAGE_FILE
        FROM {FQ}.PACKING_SLIP_HEADERS h
        {where}
        ORDER BY h.CONFIDENCE_SCORE ASC, h.HEADER_ID
    """)

    if queue.empty:
        st.info("No slips match this filter.")
    else:
        total = len(queue)
        idx = st.session_state.idx % total
        row = queue.iloc[idx]
        hid = int(row["HEADER_ID"])
        page_file = row["PAGE_FILE"]

        # Load line items into session state when slip changes
        if st.session_state.li_loaded_for != hid:
            li_df = qry(f"""
                SELECT LINE_ITEM_ID, PART_NUMBER, DESCRIPTION,
                       QUANTITY_ORDERED, QUANTITY_SHIPPED, UNIT_OF_MEASURE
                FROM {FQ}.PACKING_SLIP_LINE_ITEMS
                WHERE HEADER_ID = {hid} ORDER BY LINE_ITEM_ID
            """)
            rows = []
            for _, r in li_df.iterrows():
                rows.append({
                    "id": int(r["LINE_ITEM_ID"]),
                    "pn": str(r["PART_NUMBER"] or ""),
                    "desc": str(r["DESCRIPTION"] or ""),
                    "qo": str(r["QUANTITY_ORDERED"] or ""),
                    "qs": str(r["QUANTITY_SHIPPED"] or ""),
                    "uom": str(r["UNIT_OF_MEASURE"] or ""),
                    "new": False
                })
            st.session_state.li_rows = rows
            st.session_state.li_loaded_for = hid

        # Navigation
        c1, c2, c3 = st.columns([1, 4, 1])
        with c1:
            if st.button("< Prev"):
                st.session_state.idx = (idx - 1) % total
                st.session_state.li_loaded_for = -1
                st.experimental_rerun()
        with c2:
            st.write(f"**{idx+1}/{total}** | PO: {row['PO_NUMBER']} | {row['SUPPLIER_NAME']} | Conf: {row['CONFIDENCE_SCORE']:.2f} | {row['REVIEW_STATUS']}")
        with c3:
            if st.button("Next >"):
                st.session_state.idx = (idx + 1) % total
                st.session_state.li_loaded_for = -1
                st.experimental_rerun()

        left, right = st.columns(2)

        # LEFT: PDF image from split slips stage
        with left:
            if page_file:
                try:
                    img = session.sql(f"""
                        SELECT {FQ}.PDF_PAGE_TO_PNG(
                            BUILD_SCOPED_FILE_URL({SLIP_STAGE}, '{page_file}'), 0
                        ) AS IMG
                    """).to_pandas()
                    if not img.empty and img.iloc[0]["IMG"] is not None:
                        st.image(img.iloc[0]["IMG"])
                    else:
                        st.warning("Could not render page.")
                except Exception as e:
                    st.error(str(e))
            else:
                st.warning("No page file linked to this slip.")

        # RIGHT: Form with header fields, line items, then action buttons
        with right:
            hdr = qry(f"SELECT * FROM {FQ}.PACKING_SLIP_HEADERS WHERE HEADER_ID = {hid}")
            if not hdr.empty:
                h = hdr.iloc[0]

                with st.form(key=f"form_{hid}"):
                    # -- Header fields --
                    st.markdown("**Header Fields**")
                    po = st.text_input("PO Number", str(h["PO_NUMBER"] or ""))
                    supplier = st.text_input("Supplier", str(h["SUPPLIER_NAME"] or ""))
                    ship_date = st.text_input("Ship Date", str(h["SHIPMENT_DATE"] or ""))
                    carrier = st.text_input("Carrier", str(h["CARRIER"] or ""))
                    tracking = st.text_input("Tracking #", str(h["TRACKING_NUMBER"] or ""))
                    ship_to = st.text_input("Ship To", str(h["SHIP_TO_ADDRESS"] or ""))
                    bill_to = st.text_input("Bill To", str(h["BILL_TO_ADDRESS"] or ""))
                    received_by = st.text_input("Received By", str(h["RECEIVED_BY"] or ""))

                    # -- Line items --
                    st.markdown("**Line Items**")
                    li_inputs = []
                    for i, li in enumerate(st.session_state.li_rows):
                        lc1, lc2, lc3, lc4, lc5, lc6 = st.columns([2, 3, 1, 1, 1, 0.5])
                        with lc1:
                            pn = st.text_input("Part#", li["pn"], key=f"pn_{hid}_{i}")
                        with lc2:
                            desc = st.text_input("Desc", li["desc"], key=f"desc_{hid}_{i}")
                        with lc3:
                            qo = st.text_input("Ord", li["qo"], key=f"qo_{hid}_{i}")
                        with lc4:
                            qs = st.text_input("Ship", li["qs"], key=f"qs_{hid}_{i}")
                        with lc5:
                            uom = st.text_input("UOM", li["uom"], key=f"uom_{hid}_{i}")
                        with lc6:
                            delete = st.checkbox("X", key=f"del_{hid}_{i}", value=False)
                        li_inputs.append({"id": li.get("id"), "new": li.get("new", False),
                                          "pn": pn, "desc": desc, "qo": qo, "qs": qs, "uom": uom,
                                          "delete": delete})

                    if not st.session_state.li_rows:
                        st.caption("No line items. Use 'Add Row' below to add one.")

                    # -- Action buttons at the bottom --
                    st.markdown("---")
                    b1, b2, b3 = st.columns(3)
                    with b1:
                        do_approve = st.form_submit_button("Approve")
                    with b2:
                        do_correct = st.form_submit_button("Save Corrections")
                    with b3:
                        do_reject = st.form_submit_button("Reject")

                    if do_approve:
                        exe(f"UPDATE {FQ}.PACKING_SLIP_HEADERS SET REVIEW_STATUS='APPROVED', REVIEWED_BY=CURRENT_USER(), REVIEWED_AT=CURRENT_TIMESTAMP() WHERE HEADER_ID={hid}")
                        st.success(f"Slip {hid} approved.")
                        st.session_state.idx = (idx + 1) % total
                        st.session_state.li_loaded_for = -1

                    if do_correct:
                        exe(f"""UPDATE {FQ}.PACKING_SLIP_HEADERS
                            SET PO_NUMBER='{esc(po)}', SUPPLIER_NAME='{esc(supplier)}', SHIPMENT_DATE='{esc(ship_date)}',
                                CARRIER='{esc(carrier)}', TRACKING_NUMBER='{esc(tracking)}', SHIP_TO_ADDRESS='{esc(ship_to)}',
                                BILL_TO_ADDRESS='{esc(bill_to)}', RECEIVED_BY='{esc(received_by)}',
                                REVIEW_STATUS='CORRECTED', REVIEWED_BY=CURRENT_USER(), REVIEWED_AT=CURRENT_TIMESTAMP()
                            WHERE HEADER_ID={hid}""")
                        saved = 0
                        deleted = 0
                        for li in li_inputs:
                            if li["delete"]:
                                if not li["new"] and li["id"]:
                                    exe(f"DELETE FROM {FQ}.PACKING_SLIP_LINE_ITEMS WHERE LINE_ITEM_ID={li['id']}")
                                    deleted += 1
                            elif li["new"]:
                                exe(f"""INSERT INTO {FQ}.PACKING_SLIP_LINE_ITEMS
                                    (HEADER_ID, PART_NUMBER, DESCRIPTION, QUANTITY_ORDERED, QUANTITY_SHIPPED, UNIT_OF_MEASURE)
                                    VALUES ({hid}, '{esc(li["pn"])}', '{esc(li["desc"])}', '{esc(li["qo"])}', '{esc(li["qs"])}', '{esc(li["uom"])}')""")
                                saved += 1
                            else:
                                exe(f"""UPDATE {FQ}.PACKING_SLIP_LINE_ITEMS
                                    SET PART_NUMBER='{esc(li["pn"])}', DESCRIPTION='{esc(li["desc"])}',
                                        QUANTITY_ORDERED='{esc(li["qo"])}', QUANTITY_SHIPPED='{esc(li["qs"])}',
                                        UNIT_OF_MEASURE='{esc(li["uom"])}'
                                    WHERE LINE_ITEM_ID={li['id']}""")
                                saved += 1
                        msg = f"Saved header + {saved} line items."
                        if deleted:
                            msg += f" Deleted {deleted} rows."
                        st.success(msg)
                        st.session_state.li_loaded_for = -1

                    if do_reject:
                        exe(f"UPDATE {FQ}.PACKING_SLIP_HEADERS SET REVIEW_STATUS='REJECTED', REVIEWED_BY=CURRENT_USER(), REVIEWED_AT=CURRENT_TIMESTAMP() WHERE HEADER_ID={hid}")
                        st.warning(f"Slip {hid} rejected.")
                        st.session_state.idx = (idx + 1) % total
                        st.session_state.li_loaded_for = -1

                # Add row button (outside form so it takes effect immediately)
                if st.button("+ Add Line Item"):
                    st.session_state.li_rows.append({
                        "id": None, "pn": "", "desc": "", "qo": "", "qs": "", "uom": "EA", "new": True
                    })
                    st.experimental_rerun()

# ============================================================
# TAB 2: DASHBOARD
# ============================================================
with tab2:
    st.header("Pipeline Dashboard")

    c1, c2, c3, c4, c5 = st.columns(5)
    c1.metric("PDFs Processed", int(qry(f"SELECT COUNT(*) N FROM {FQ}.AI_COMPLETE_EXTRACTIONS").iloc[0]["N"]))
    c2.metric("Slips Extracted", int(qry(f"SELECT COUNT(*) N FROM {FQ}.PACKING_SLIP_HEADERS").iloc[0]["N"]))
    c3.metric("Line Items", int(qry(f"SELECT COUNT(*) N FROM {FQ}.PACKING_SLIP_LINE_ITEMS").iloc[0]["N"]))
    c4.metric("Pending Review", int(qry(f"SELECT COUNT(*) N FROM {FQ}.PACKING_SLIP_HEADERS WHERE REVIEW_STATUS IN ('NEEDS_REVIEW','SPOT_CHECK','PENDING')").iloc[0]["N"]))
    c5.metric("Approved", int(qry(f"SELECT COUNT(*) N FROM {FQ}.PACKING_SLIP_HEADERS WHERE REVIEW_STATUS IN ('AUTO_APPROVED','APPROVED')").iloc[0]["N"]))

    st.markdown("---")

    col_left, col_right = st.columns(2)
    with col_left:
        st.subheader("Review Status Breakdown")
        st.dataframe(qry(f"""
            SELECT REVIEW_STATUS, COUNT(*) AS SLIP_COUNT,
                   ROUND(AVG(CONFIDENCE_SCORE), 2) AS AVG_CONFIDENCE,
                   ROUND(MIN(CONFIDENCE_SCORE), 2) AS MIN_CONFIDENCE,
                   ROUND(MAX(CONFIDENCE_SCORE), 2) AS MAX_CONFIDENCE
            FROM {FQ}.PACKING_SLIP_HEADERS GROUP BY 1 ORDER BY SLIP_COUNT DESC
        """))
    with col_right:
        st.subheader("Confidence Distribution")
        st.dataframe(qry(f"""
            SELECT CASE
                WHEN CONFIDENCE_SCORE >= 0.90 THEN '0.90 - 1.00 (High)'
                WHEN CONFIDENCE_SCORE >= 0.80 THEN '0.80 - 0.89'
                WHEN CONFIDENCE_SCORE >= 0.60 THEN '0.60 - 0.79'
                ELSE 'Below 0.60 (Low)' END AS CONFIDENCE_RANGE,
                COUNT(*) AS SLIP_COUNT
            FROM {FQ}.PACKING_SLIP_HEADERS GROUP BY 1 ORDER BY 1
        """))

    st.markdown("---")

    col_left2, col_right2 = st.columns(2)
    with col_left2:
        st.subheader("Top Suppliers by Volume")
        st.dataframe(qry(f"""
            SELECT COALESCE(h.SUPPLIER_NAME, '(unknown)') AS SUPPLIER,
                COUNT(DISTINCT h.HEADER_ID) AS SLIPS,
                COUNT(DISTINCT li.LINE_ITEM_ID) AS LINE_ITEMS,
                ROUND(AVG(h.CONFIDENCE_SCORE), 2) AS AVG_CONF
            FROM {FQ}.PACKING_SLIP_HEADERS h
            LEFT JOIN {FQ}.PACKING_SLIP_LINE_ITEMS li ON h.HEADER_ID = li.HEADER_ID
            GROUP BY 1 ORDER BY SLIPS DESC LIMIT 15
        """))
    with col_right2:
        st.subheader("Documents Processed")
        st.dataframe(qry(f"""
            SELECT e.FILE_NAME, p.PAGE_COUNT AS PAGES, e.SLIP_COUNT AS SLIPS,
                (SELECT COUNT(*) FROM {FQ}.PACKING_SLIP_LINE_ITEMS li
                 JOIN {FQ}.PACKING_SLIP_HEADERS h ON li.HEADER_ID = h.HEADER_ID
                 WHERE h.EXTRACTION_ID = e.EXTRACTION_ID) AS LINE_ITEMS,
                ROUND((SELECT AVG(CONFIDENCE_SCORE) FROM {FQ}.PACKING_SLIP_HEADERS
                       WHERE EXTRACTION_ID = e.EXTRACTION_ID), 2) AS AVG_CONF
            FROM {FQ}.AI_COMPLETE_EXTRACTIONS e
            LEFT JOIN {FQ}.PARSED_DOCUMENTS p ON e.FILE_NAME = p.FILE_NAME
            ORDER BY e.EXTRACTED_AT DESC
        """))

    st.markdown("---")

    col_left3, col_right3 = st.columns(2)
    with col_left3:
        st.subheader("Line Item Summary")
        li_stats = qry(f"""
            SELECT COUNT(*) AS TOTAL_LINE_ITEMS,
                COUNT(CASE WHEN PART_NUMBER IS NOT NULL AND PART_NUMBER != '' THEN 1 END) AS WITH_PART_NUMBER,
                COUNT(CASE WHEN DESCRIPTION IS NOT NULL AND DESCRIPTION != '' THEN 1 END) AS WITH_DESCRIPTION,
                COUNT(CASE WHEN QUANTITY_SHIPPED IS NOT NULL AND QUANTITY_SHIPPED != '' THEN 1 END) AS WITH_QTY_SHIPPED
            FROM {FQ}.PACKING_SLIP_LINE_ITEMS
        """)
        if not li_stats.empty:
            r = li_stats.iloc[0]
            t = int(r["TOTAL_LINE_ITEMS"])
            st.write(f"**{t}** total line items extracted")
            if t > 0:
                st.write(f"- Part number: **{int(r['WITH_PART_NUMBER'])*100//t}%** ({int(r['WITH_PART_NUMBER'])}/{t})")
                st.write(f"- Description: **{int(r['WITH_DESCRIPTION'])*100//t}%** ({int(r['WITH_DESCRIPTION'])}/{t})")
                st.write(f"- Qty shipped: **{int(r['WITH_QTY_SHIPPED'])*100//t}%** ({int(r['WITH_QTY_SHIPPED'])}/{t})")
    with col_right3:
        st.subheader("Header Field Completeness")
        f = qry(f"""
            SELECT COUNT(*) AS T,
                ROUND(COUNT(CASE WHEN PO_NUMBER IS NOT NULL AND PO_NUMBER != '' THEN 1 END)*100.0/COUNT(*)) AS PO,
                ROUND(COUNT(CASE WHEN SUPPLIER_NAME IS NOT NULL AND SUPPLIER_NAME != '' THEN 1 END)*100.0/COUNT(*)) AS SUPP,
                ROUND(COUNT(CASE WHEN SHIPMENT_DATE IS NOT NULL AND SHIPMENT_DATE != '' THEN 1 END)*100.0/COUNT(*)) AS DT,
                ROUND(COUNT(CASE WHEN CARRIER IS NOT NULL AND CARRIER != '' THEN 1 END)*100.0/COUNT(*)) AS CARR,
                ROUND(COUNT(CASE WHEN TRACKING_NUMBER IS NOT NULL AND TRACKING_NUMBER != '' THEN 1 END)*100.0/COUNT(*)) AS TRACK,
                ROUND(COUNT(CASE WHEN SHIP_TO_ADDRESS IS NOT NULL AND SHIP_TO_ADDRESS != '' THEN 1 END)*100.0/COUNT(*)) AS SHIP,
                ROUND(COUNT(CASE WHEN RECEIVED_BY IS NOT NULL AND RECEIVED_BY != '' THEN 1 END)*100.0/COUNT(*)) AS RECV
            FROM {FQ}.PACKING_SLIP_HEADERS
        """)
        if not f.empty:
            r = f.iloc[0]
            st.write(f"Across **{int(r['T'])}** slips:")
            st.write(f"- PO Number: **{int(r['PO'])}%**")
            st.write(f"- Supplier: **{int(r['SUPP'])}%**")
            st.write(f"- Ship Date: **{int(r['DT'])}%**")
            st.write(f"- Carrier: **{int(r['CARR'])}%**")
            st.write(f"- Tracking #: **{int(r['TRACK'])}%**")
            st.write(f"- Ship-To: **{int(r['SHIP'])}%**")
            st.write(f"- Received By: **{int(r['RECV'])}%**")

    st.markdown("---")
    st.subheader("Extraction Errors")
    errs = qry(f"SELECT FILE_NAME, ERROR_MESSAGE, PIPELINE_STEP, ERROR_TIMESTAMP FROM {FQ}.EXTRACTION_ERRORS ORDER BY ERROR_TIMESTAMP DESC LIMIT 20")
    if not errs.empty:
        st.dataframe(errs)
    else:
        st.success("No extraction errors.")
