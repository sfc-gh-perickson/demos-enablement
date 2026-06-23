-- =============================================================================
-- PII Redaction Lab: Setup Script
-- =============================================================================
-- Run this script once before starting the notebook.
-- It creates all prerequisite objects: database, warehouse, sample data,
-- the REDACT_PII UDF, and the PII entity cache table.
--
-- Prerequisites:
--   - A role with CREATE DATABASE, CREATE WAREHOUSE privileges
--   - Cross-region inference enabled (for Cortex AI functions)
--   - SNOWFLAKE.CORTEX_USER database role granted to your role
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE AND SCHEMA
-- ─────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS PII_REDACTION_DEMO;
USE DATABASE PII_REDACTION_DEMO;
CREATE SCHEMA IF NOT EXISTS REDACTION;
USE SCHEMA REDACTION;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. WAREHOUSE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE WAREHOUSE IF NOT EXISTS PII_REDACTION_WH
  WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND = 120
  AUTO_RESUME = TRUE;

USE WAREHOUSE PII_REDACTION_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. DOCUMENT_CHUNKS TABLE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE DOCUMENT_CHUNKS (
    DOC_ID       VARCHAR,
    CHUNK_INDEX  NUMBER,
    CHUNK_TEXT   VARCHAR,
    DOC_TYPE     VARCHAR
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. SYNTHETIC DATA (200 chunks across 20 documents)
-- ─────────────────────────────────────────────────────────────────────────────

-- Document 1: Contract (10 chunks)
INSERT INTO DOCUMENT_CHUNKS VALUES
('DOC-001', 1, 'MASTER SERVICE AGREEMENT between Northwind Industries LLC and Contoso Corp. This agreement is entered into as of January 15, 2024 by and between the parties listed herein for the provision of cloud data services.', 'contract'),
('DOC-001', 2, 'Primary Contact: Sarah Mitchell, VP of Engineering, email: sarah.mitchell@northwind.com, phone: (415) 555-0142. All notices under this agreement shall be directed to the primary contact at 2847 Market Street, Suite 400, San Francisco, CA 94105.', 'contract'),
('DOC-001', 3, 'Payment terms are Net 30 from date of invoice. Wire transfers should reference account holder Northwind Industries LLC. Monthly service fee of $45,000 commences on the effective date and is subject to annual CPI adjustment.', 'contract'),
('DOC-001', 4, 'The term of this agreement shall be thirty-six (36) months from the effective date, with automatic renewal for successive twelve-month periods unless either party provides written notice of non-renewal at least ninety (90) days prior to the end of the then-current term.', 'contract'),
('DOC-001', 5, 'Authorized signatory for Northwind Industries: James Chen, Chief Executive Officer, SSN ending in 4521 (for tax purposes). Federal Tax ID: 82-4917356. Signatory DOB: March 12, 1978.', 'contract'),
('DOC-001', 6, 'Confidentiality obligations survive termination for a period of five (5) years. Neither party shall disclose proprietary information without prior written consent. Trade secrets are protected indefinitely under applicable state law.', 'contract'),
('DOC-001', 7, 'Service Level Agreement: 99.9% uptime guarantee measured on a monthly basis. Credits issued for downtime exceeding 0.1% per calendar month. Planned maintenance windows excluded from availability calculations.', 'contract'),
('DOC-001', 8, 'Insurance requirements: Provider shall maintain commercial general liability insurance of not less than $2,000,000 per occurrence and $5,000,000 aggregate. Certificates of insurance shall be provided annually.', 'contract'),
('DOC-001', 9, 'Dispute Resolution: Any controversy arising under this agreement shall be settled by binding arbitration administered by JAMS in San Francisco, California. The arbitration shall be governed by the Federal Arbitration Act.', 'contract'),
('DOC-001', 10, 'Secondary contact: David Park, Legal Counsel, david.park@northwind.com, direct line: (415) 555-0198. Billing inquiries should be directed to accounts@northwind.com or mailed to PO Box 4421, San Francisco, CA 94119.', 'contract'),

-- Document 2: Email thread (12 chunks)
('DOC-002', 1, 'From: jennifer.walsh@acmecorp.io\nTo: support@dataplatform.com\nDate: 2024-03-18 09:14 AM\nSubject: Urgent - Production data exposure incident\n\nHi Support Team,\n\nWe discovered that our production warehouse may have exposed customer PII in query logs. Need immediate assistance.', 'email'),
('DOC-002', 2, 'The affected table CUSTOMERS_RAW contains approximately 340,000 records with full names, email addresses, and phone numbers. We identified the issue during a routine audit by our DBA, Marcus Johnson, at approximately 2:47 AM Pacific time.', 'email'),
('DOC-002', 3, 'Affected customer records include entries like: Robert Anderson (robert.anderson@gmail.com, 503-555-0167), Patricia Lee (patricia.lee@outlook.com, 212-555-0834), and approximately 12,000 others with similar exposure patterns.', 'email'),
('DOC-002', 4, 'Our compliance officer Maria Santos (maria.santos@acmecorp.io, ext. 4455) has been notified and is preparing the incident report for our board meeting on Thursday. Please confirm receipt and provide an estimated response time.', 'email'),
('DOC-002', 5, 'Best regards,\nJennifer Walsh\nDirector of Data Engineering\nAcme Corporation\nPhone: (628) 555-0291\nAddress: 1200 Technology Drive, Building C, Austin, TX 78701', 'email'),
('DOC-002', 6, 'From: support@dataplatform.com\nTo: jennifer.walsh@acmecorp.io\nDate: 2024-03-18 10:02 AM\n\nHi Jennifer,\n\nThank you for reporting this promptly. We are escalating to our security team immediately. Ticket #INC-2024-0847 has been created.', 'email'),
('DOC-002', 7, 'Based on your description, the exposure appears limited to query history logs rather than direct table access. We recommend immediately rotating any API keys associated with the affected service account (SA-PROD-DW-041).', 'email'),
('DOC-002', 8, 'Our security analyst Kevin O''Brien will be your primary point of contact. He can be reached at kevin.obrien@dataplatform.com or (800) 555-0100 ext. 2291 during business hours Pacific time.', 'email'),
('DOC-002', 9, 'We will provide a preliminary root cause analysis within 4 business hours. In the meantime, please ensure that masking policies are applied to all columns containing PII in the affected schemas.', 'email'),
('DOC-002', 10, 'Additionally, we recommend reviewing access grants for the following roles that had SELECT privileges on CUSTOMERS_RAW: ANALYST_ROLE, REPORTING_ROLE, and DATA_SCIENCE_ROLE. Audit logs are available in SNOWFLAKE.ACCOUNT_USAGE.', 'email'),
('DOC-002', 11, 'Standard remediation steps include: 1) Apply dynamic masking to sensitive columns, 2) Revoke broad SELECT grants, 3) Enable row access policies for row-level security, 4) Set up alerts on future unmasked access attempts.', 'email'),
('DOC-002', 12, 'Please note that under your enterprise agreement (Contract #ENT-2023-4419), you are entitled to priority incident response with a 2-hour SLA. We are treating this accordingly.', 'email'),

-- Document 3: Support ticket (8 chunks)
('DOC-003', 1, 'Ticket #SUP-29841 | Priority: High | Created: 2024-02-07 14:22 PST\nReporter: Amanda Foster (amanda.foster@healthsys.org)\nSubject: Patient data visible in shared dashboard', 'support_ticket'),
('DOC-003', 2, 'Description: During a routine review of our analytics dashboards, we noticed that patient names and dates of birth are appearing in the executive summary view. This view is accessible to non-clinical staff who should not have access to PHI.', 'support_ticket'),
('DOC-003', 3, 'Example records visible: Patient Michael Torres, DOB: 07/23/1985, MRN: MRN-4472891. Patient Elena Rodriguez, DOB: 11/02/1992, MRN: MRN-5518234. These should be masked or excluded from this particular view.', 'support_ticket'),
('DOC-003', 4, 'The dashboard pulls from view V_PATIENT_SUMMARY which joins PATIENT_DEMOGRAPHICS and ENCOUNTER_HISTORY. The masking policy was supposed to apply to all non-clinical roles but appears to be bypassed when accessed through the BI tool.', 'support_ticket'),
('DOC-003', 5, 'Assigned to: Technical Support Engineer Lisa Chang (lisa.chang@dataplatform.com). Initial assessment: The dynamic masking policy on PATIENT_NAME and DATE_OF_BIRTH columns is correctly defined but not applied when the BI tool uses a service account.', 'support_ticket'),
('DOC-003', 6, 'Resolution steps: 1) Identified that BI service account BI_SVC_ACCT was granted CLINICAL_ANALYST role directly, bypassing intended masking. 2) Revoked CLINICAL_ANALYST from BI_SVC_ACCT. 3) Created new role BI_DASHBOARD_ROLE with appropriate masking policies.', 'support_ticket'),
('DOC-003', 7, 'Customer confirmed fix is working. All PHI now displays as masked values (e.g., "M****** T*****") in the executive dashboard. No evidence of unauthorized data export during the exposure window based on access_history review.', 'support_ticket'),
('DOC-003', 8, 'Follow-up: Scheduled compliance review with Amanda Foster and CISO Brian Nakamura (brian.nakamura@healthsys.org) for next Tuesday to discuss implementing column-level audit logging on all PHI columns.', 'support_ticket'),

-- Document 4: Medical note (10 chunks)
('DOC-004', 1, 'PATIENT ENCOUNTER NOTE\nDate: 2024-04-11\nProvider: Dr. Rachel Kim, MD (NPI: 1234567890)\nFacility: Westside Medical Center, 500 Healthcare Blvd, Portland, OR 97201', 'medical_note'),
('DOC-004', 2, 'Patient: William Foster, DOB: 09/14/1962, MRN: WMC-00284716\nInsurance: BlueCross BlueShield, Policy #: BCB-44891-W\nEmergency Contact: Catherine Foster (wife), (503) 555-0284', 'medical_note'),
('DOC-004', 3, 'Chief Complaint: Patient presents with persistent lower back pain radiating to left leg, duration 3 weeks. Pain rated 7/10 on visual analog scale. No improvement with over-the-counter NSAIDs.', 'medical_note'),
('DOC-004', 4, 'Physical Examination: Alert and oriented x4. Gait antalgic. Lumbar spine tender to palpation at L4-L5. Straight leg raise positive on left at 45 degrees. Strength 4/5 left ankle dorsiflexion. Reflexes symmetric and intact bilaterally.', 'medical_note'),
('DOC-004', 5, 'Assessment: Lumbar radiculopathy, likely L4-L5 disc herniation with left L5 nerve root compression. Differential includes spinal stenosis given patient age and presentation.', 'medical_note'),
('DOC-004', 6, 'Plan: Order MRI lumbar spine without contrast. Prescribe gabapentin 300mg TID for neuropathic pain. Refer to physical therapy 2x/week for 6 weeks. Follow up in 3 weeks with imaging results.', 'medical_note'),
('DOC-004', 7, 'Referral sent to Dr. Anthony Patel, Physical Medicine & Rehabilitation, Westside PT Clinic. Patient prefers Tuesday/Thursday morning appointments. Referral #REF-2024-11847.', 'medical_note'),
('DOC-004', 8, 'Medications reconciled: Current medications include lisinopril 10mg daily, atorvastatin 20mg daily, and aspirin 81mg daily. No drug interactions with gabapentin noted. Pharmacy: Walgreens #4412, 1800 NW 23rd Ave, Portland, OR 97210.', 'medical_note'),
('DOC-004', 9, 'Patient education provided regarding activity modification, proper lifting mechanics, and red flag symptoms requiring immediate evaluation (bowel/bladder dysfunction, progressive weakness, saddle anesthesia). Patient verbalized understanding.', 'medical_note'),
('DOC-004', 10, 'Electronically signed by Dr. Rachel Kim, MD on 2024-04-11 at 16:42 PST. Encounter duration: 35 minutes. Next appointment: 2024-05-02 at 10:30 AM with Dr. Kim.', 'medical_note'),

-- Document 5: Financial report (10 chunks)
('DOC-005', 1, 'QUARTERLY FINANCIAL REVIEW — Q1 2024\nPrepared by: Chief Financial Officer Thomas Wright\nDistribution: Board of Directors, Executive Leadership Team\nClassification: CONFIDENTIAL — Internal Use Only', 'financial_report'),
('DOC-005', 2, 'Revenue summary: Total Q1 revenue of $14.2M represents a 12% year-over-year increase. Subscription revenue grew 18% to $11.1M while professional services contributed $3.1M. No material customer concentration risk identified.', 'financial_report'),
('DOC-005', 3, 'Operating expenses totaled $12.8M, with headcount costs of $8.9M (156 FTEs). Notable new hires include VP of Sales Christina Vasquez and Senior Director of Product Alex Nguyen. Average fully-loaded cost per employee: $57,051/quarter.', 'financial_report'),
('DOC-005', 4, 'Cash position: $28.4M in operating accounts (First Republic Bank, acct ending 7892). Line of credit facility of $15M with Silicon Valley Bank remains undrawn. Burn rate of $1.2M/month at current growth trajectory.', 'financial_report'),
('DOC-005', 5, 'Accounts receivable aging: $3.2M total outstanding. 87% current (0-30 days), 9% at 31-60 days, 4% at 61-90 days. Largest outstanding: Meridian Health Systems ($420K, 45 days). Write-off provision of $85K maintained.', 'financial_report'),
('DOC-005', 6, 'Capital expenditures of $890K primarily driven by new office buildout at 3500 Innovation Way, Denver, CO 80202. Lease signed for 15,000 sq ft at $42/sq ft, 7-year term commencing April 2024.', 'financial_report'),
('DOC-005', 7, 'Tax planning: Estimated Q1 federal tax liability of $280K. R&D tax credits of $145K identified for qualifying activities. Tax advisor: Deloitte (engagement partner: Sandra Phillips, sandra.phillips@deloitte.com).', 'financial_report'),
('DOC-005', 8, 'Key risk factors: Potential tariff impacts on cloud infrastructure costs (estimated 5-8% increase). Currency exposure limited to EUR/USD on European contracts totaling $1.8M annually. Hedging strategy under review.', 'financial_report'),
('DOC-005', 9, 'Board compensation: Total Q1 board compensation of $320K. Director fees of $40K/quarter per independent director. Stock option grants of 25,000 shares each to new directors Michelle Chang and Robert Blackwell vesting over 4 years.', 'financial_report'),
('DOC-005', 10, 'Outlook: Management reaffirms full-year revenue guidance of $62-65M. Pipeline coverage of 3.2x provides confidence. Key assumption: successful enterprise product launch in Q3 contributing $4M+ in H2 bookings.', 'financial_report'),

-- Document 6: Contract (8 chunks)
('DOC-006', 1, 'DATA PROCESSING AGREEMENT\nProcessor: Apex Analytics Inc.\nController: Sterling Financial Group\nEffective Date: February 1, 2024\nDPO Contact: Rebecca Torres, privacy@sterlingfin.com, +1 (312) 555-0467', 'contract'),
('DOC-006', 2, 'Purpose: Processor shall process personal data solely for the purpose of providing advanced analytics and reporting services as described in Schedule A. Processing includes aggregation, statistical analysis, and anonymized reporting.', 'contract'),
('DOC-006', 3, 'Data subjects: Customers of Controller residing in the United States, European Economic Area, and United Kingdom. Estimated volume: 2.4 million data subjects. Categories of data: name, email, transaction history, account balances.', 'contract'),
('DOC-006', 4, 'Sub-processors: Processor engages the following sub-processors: Amazon Web Services (us-east-1, us-west-2), Snowflake Inc. (AWS US West), Fivetran Inc. (data pipeline services). Controller has approved all sub-processors listed herein.', 'contract'),
('DOC-006', 5, 'Processor technical contact: Daniel Okafor, Lead Data Engineer, daniel.okafor@apexanalytics.com, (650) 555-0392. All data breach notifications shall be communicated within 72 hours to the Controller DPO.', 'contract'),
('DOC-006', 6, 'Data retention: Personal data shall be deleted or returned within 30 days of contract termination. Processor shall provide written certification of deletion. Backup copies shall be purged within 90 days following the retention period.', 'contract'),
('DOC-006', 7, 'Security measures: AES-256 encryption at rest, TLS 1.3 in transit. Annual SOC 2 Type II audit. Penetration testing performed quarterly by independent third party. Employee background checks required for all personnel with data access.', 'contract'),
('DOC-006', 8, 'Governing law: This DPA shall be governed by the laws of the State of Illinois. In the event of conflict between this DPA and the underlying Master Services Agreement (#MSA-2023-1847), this DPA shall prevail regarding data protection matters.', 'contract'),

-- Document 7: Email (10 chunks)
('DOC-007', 1, 'From: hr@globaltech.com\nTo: new-hires-march-2024@globaltech.com\nSubject: Welcome Aboard - Onboarding Information\nDate: 2024-03-01\n\nDear New Team Members,\n\nWelcome to GlobalTech Solutions! We are excited to have you join our team.', 'email'),
('DOC-007', 2, 'Please complete the following forms before your first day:\n- W-4 (Federal Tax Withholding)\n- I-9 (Employment Eligibility Verification)\n- Direct deposit form (bring a voided check or bank routing/account numbers)\n- Emergency contact information', 'email'),
('DOC-007', 3, 'New hire orientation schedule for March 4, 2024:\n9:00 AM - Badge photos and ID activation (Lobby, Building A)\n10:00 AM - HR overview with Samantha Reed (Conference Room 3B)\n11:30 AM - IT setup with your assigned buddy', 'email'),
('DOC-007', 4, 'IT Account Information:\nYour temporary credentials will be emailed separately. Default password format is: GT_[FirstInitial][LastName]_2024! (example: GT_JSmith_2024!). You will be prompted to change this on first login.', 'email'),
('DOC-007', 5, 'Parking: Employee parking is available in Garage B, levels 3-5. Your badge will activate garage access after orientation. Visitor parking in Lot C is available for your first day. Office address: 8900 Enterprise Parkway, Suite 200, Raleigh, NC 27615.', 'email'),
('DOC-007', 6, 'Benefits enrollment opens on your start date and closes 30 days later. Benefits coordinator: Monica Alvarez, monica.alvarez@globaltech.com, ext. 5512. Health, dental, vision, 401(k) with 4% match, and ESPP are available.', 'email'),
('DOC-007', 7, 'Your hiring manager will reach out separately with team-specific details. Please confirm receipt of this email by replying to hr@globaltech.com. If you have questions, contact Lisa Park at (919) 555-0344.', 'email'),
('DOC-007', 8, 'Required documents to bring on Day 1: Government-issued photo ID (passport or driver license), Social Security card or birth certificate, signed offer letter. Dress code is business casual.', 'email'),
('DOC-007', 9, 'Technology equipment: You will receive a company laptop (MacBook Pro or Dell XPS based on role), monitor, keyboard, and mouse. Remote workers will receive a home office stipend of $500. Equipment contact: IT Help Desk, helpdesk@globaltech.com.', 'email'),
('DOC-007', 10, 'We look forward to seeing you on March 4th!\n\nBest regards,\nHuman Resources Team\nGlobalTech Solutions\n8900 Enterprise Parkway, Suite 200\nRaleigh, NC 27615\nPhone: (919) 555-0300', 'email'),

-- Document 8: Support ticket (10 chunks)
('DOC-008', 1, 'Ticket #SUP-31205 | Priority: Critical | Created: 2024-05-14 08:15 EST\nReporter: Nathan Brooks (nathan.brooks@retailcorp.com)\nOrganization: RetailCorp International\nSubject: Credit card numbers appearing in application logs', 'support_ticket'),
('DOC-008', 2, 'Description: Our application logging pipeline is inadvertently capturing full credit card numbers in the raw event stream. We discovered entries containing card numbers like 4532-XXXX-XXXX-8901 and 5421-XXXX-XXXX-3344 in plaintext within our EVENTS_RAW table.', 'support_ticket'),
('DOC-008', 3, 'Impact assessment: Approximately 14,000 log entries over the past 72 hours contain unmasked payment card data. This affects PCI-DSS compliance. Our QSA (Qualified Security Assessor) has been notified.', 'support_ticket'),
('DOC-008', 4, 'Immediate actions taken: 1) Disabled the logging endpoint that was capturing card data. 2) Revoked SELECT access to EVENTS_RAW for all non-security roles. 3) Engaged our PCI forensic investigator: SecureForensics LLC, contact: Diana Mendez, diana.mendez@secureforensics.com.', 'support_ticket'),
('DOC-008', 5, 'Root cause: The payment processing module was logging the full HTTP request body instead of the sanitized version. The log redaction filter (regex-based) failed to match card numbers with dashes and spaces. Fix deployed to staging.', 'support_ticket'),
('DOC-008', 6, 'Requesting: 1) Assistance implementing a masking policy on EVENTS_RAW for any column matching credit card patterns. 2) Guidance on data deletion procedures for PCI compliance. 3) Audit log export for the affected time window.', 'support_ticket'),
('DOC-008', 7, 'Escalation contact: VP of Security, Christopher Yang, christopher.yang@retailcorp.com, mobile: (404) 555-0876. Available 24/7 for this incident. PCI compliance deadline: remediation must be complete within 48 hours of detection.', 'support_ticket'),
('DOC-008', 8, 'Technical details: The affected table has 2.3M total rows across the 72-hour window. Card data appears in column EVENT_PAYLOAD (VARIANT type). Regex pattern used: [0-9]{4}[-\\s]?[0-9]{4}[-\\s]?[0-9]{4}[-\\s]?[0-9]{4} identifies approximately 14,200 matches.', 'support_ticket'),
('DOC-008', 9, 'Our current masking approach uses a static regex, which is how we missed the dashed format. We are interested in exploring AI-based redaction that can identify card numbers regardless of formatting. Can you demonstrate AI_REDACT or similar capabilities?', 'support_ticket'),
('DOC-008', 10, 'Resolution timeline: Must resolve by 2024-05-16 08:00 EST per PCI incident response requirements. If unresolved, we are required to notify our acquiring bank (Chase Merchant Services, merchant ID: MID-7829441) and potentially suspend card processing.', 'support_ticket'),

-- Document 9: Medical note (12 chunks)
('DOC-009', 1, 'DISCHARGE SUMMARY\nFacility: Riverside General Hospital\nUnit: Cardiology, 4th Floor\nAdmission Date: 2024-03-28\nDischarge Date: 2024-04-01\nAttending Physician: Dr. Samuel Washington, MD, FACC', 'medical_note'),
('DOC-009', 2, 'Patient: Margaret O''Connor, DOB: 12/05/1948, Age: 75\nMRN: RGH-10042897\nSSN: XXX-XX-6714 (last four for verification)\nInsurance: Medicare Part A, HIC#: 1EG4-TE5-MK72', 'medical_note'),
('DOC-009', 3, 'Admitting Diagnosis: Acute myocardial infarction (STEMI), anterior wall\nDischarge Diagnosis: Status post primary PCI with drug-eluting stent to LAD\nSecondary: Hypertension, Type 2 Diabetes Mellitus, Hyperlipidemia', 'medical_note'),
('DOC-009', 4, 'Hospital Course: Patient presented to ED via EMS with acute chest pain and ST elevation in leads V1-V4. Door-to-balloon time was 47 minutes. Successful primary PCI performed with deployment of 3.0 x 18mm Xience Sierra stent to mid-LAD with TIMI 3 flow restored.', 'medical_note'),
('DOC-009', 5, 'Post-procedure course uncomplicated. Peak troponin 28.4 ng/mL. Echocardiogram showed LVEF 45% with anterior hypokinesis. No hemodynamic instability, arrhythmias, or mechanical complications during admission.', 'medical_note'),
('DOC-009', 6, 'Discharge Medications:\n1. Aspirin 81mg daily (indefinite)\n2. Clopidogrel 75mg daily (minimum 12 months)\n3. Atorvastatin 80mg daily\n4. Metoprolol succinate 50mg daily\n5. Lisinopril 10mg daily\n6. Metformin 1000mg BID (continue home med)', 'medical_note'),
('DOC-009', 7, 'Cardiac Rehabilitation: Referral placed to Riverside Cardiac Rehab Program. Intake appointment scheduled for 2024-04-08 at 9:00 AM. Program coordinator: nurse Stephanie Lee, (503) 555-0429.', 'medical_note'),
('DOC-009', 8, 'Follow-up: Cardiology clinic in 2 weeks (2024-04-15) with Dr. Washington. PCP follow-up in 1 week with Dr. Helen Nakamura at Portland Family Medicine, (503) 555-0511.', 'medical_note'),
('DOC-009', 9, 'Patient Education: Discussed post-MI activity restrictions, medication compliance, dietary modifications (low sodium, heart-healthy diet), smoking cessation (patient reports quitting 2019), and warning signs requiring immediate medical attention.', 'medical_note'),
('DOC-009', 10, 'Emergency Contact: Thomas O''Connor (son), (503) 555-0662. Home address: 4217 SE Hawthorne Blvd, Portland, OR 97215. Patient will be staying with son for first 2 weeks post-discharge.', 'medical_note'),
('DOC-009', 11, 'Activity restrictions: No driving for 1 week. No lifting >10 lbs for 2 weeks. May resume light walking immediately. Cardiac rehab will provide graduated exercise protocol. Return to normal activities guided by cardiac rehab team.', 'medical_note'),
('DOC-009', 12, 'Dictated by: Dr. Samuel Washington, MD, FACC\nElectronically signed: 2024-04-01 14:22 PST\nCopies sent to: Dr. Helen Nakamura (PCP), Riverside Cardiac Rehab, Patient portal', 'medical_note'),

-- Document 10: Financial report (10 chunks)
('DOC-010', 1, 'ANNUAL COMPENSATION REVIEW — CONFIDENTIAL\nHR Business Partner: Vanessa Hughes\nReview Period: FY2024\nDepartment: Engineering\nDate Prepared: 2024-01-15', 'financial_report'),
('DOC-010', 2, 'Total engineering headcount: 89 employees across 6 teams. Median base salary: $185,000. Total compensation (base + equity + bonus) median: $265,000. Attrition rate FY2023: 8.2% (below industry average of 13.1%).', 'financial_report'),
('DOC-010', 3, 'Recommended adjustments:\n- Senior Engineer Ryan Patel: $175K → $195K (market adjustment, 11.4% increase). Currently 15% below band midpoint. Flight risk — received competing offer from competitor.\n- Staff Engineer Maria Gonzalez: $210K → $225K (promotion to Principal). Exceptional performance rating.', 'financial_report'),
('DOC-010', 4, 'Equity refresh grants recommended:\n- Jessica Huang (Engineering Manager): 15,000 RSUs, 4-year vest. Critical retention target — owns key system architecture knowledge.\n- Oliver Thompson (Senior SRE): 10,000 RSUs, 4-year vest. Led zero-downtime migration project.', 'financial_report'),
('DOC-010', 5, 'Compensation band analysis: 12 employees below band minimum (mostly recent hires from FY2022 who missed last cycle). Total cost to bring to minimum: $340K annually. Recommend immediate adjustment to reduce turnover risk.', 'financial_report'),
('DOC-010', 6, 'Benefits utilization: 78% enrolled in high-deductible health plan. 401(k) participation at 94% with average contribution of 8.2%. ESPP participation at 62%. Mental health benefit usage increased 23% year-over-year.', 'financial_report'),
('DOC-010', 7, 'Diversity metrics: Engineering department is 34% women (up from 29% in FY2022), 22% underrepresented minorities. Senior+ roles: 28% women, 18% URM. Pipeline improvements needed at Staff+ level.', 'financial_report'),
('DOC-010', 8, 'Budget request: Total FY2025 compensation budget increase of $2.1M (8.4% over FY2024). Breakdown: $890K merit increases, $450K market adjustments, $340K band corrections, $420K new headcount (6 approved reqs).', 'financial_report'),
('DOC-010', 9, 'Key risks: Three Staff+ engineers have been approached by competitors in the past quarter. Specific retention concerns: Jason Mitchell (Staff Platform), Sarah Kim (Principal Data), and Alex Rivera (Staff ML). All have unvested equity <$50K remaining.', 'financial_report'),
('DOC-010', 10, 'Approval chain: VP Engineering (Michael Torres) → CFO (Thomas Wright) → CEO (pending). Target approval date: February 15, 2024. Effective date for adjustments: March 1, 2024 payroll.', 'financial_report'),

-- Document 11: Contract (10 chunks)
('DOC-011', 1, 'NON-DISCLOSURE AGREEMENT\nParties: TechForward Inc. ("Disclosing Party") and Quantum Dynamics LLC ("Receiving Party")\nEffective Date: 2024-05-01\nExpiration: 2026-04-30 (24-month term)', 'contract'),
('DOC-011', 2, 'Disclosing Party Representative: Angela Morrison, VP Business Development, angela.morrison@techforward.io, (858) 555-0244, 4200 Torrey Pines Road, Suite 110, La Jolla, CA 92037.', 'contract'),
('DOC-011', 3, 'Receiving Party Representative: Raj Krishnamurthy, CTO, raj.k@quantumdynamics.ai, (617) 555-0819, 75 Cambridge Parkway, Cambridge, MA 02142.', 'contract'),
('DOC-011', 4, 'Confidential Information includes but is not limited to: product roadmaps, customer lists, pricing models, proprietary algorithms, source code, financial projections, merger and acquisition plans, and any information marked "Confidential" or reasonably understood to be confidential.', 'contract'),
('DOC-011', 5, 'Exclusions from Confidential Information: information that (a) is or becomes publicly available through no fault of Receiving Party, (b) was rightfully in possession of Receiving Party prior to disclosure, (c) is independently developed without reference to Confidential Information.', 'contract'),
('DOC-011', 6, 'Receiving Party shall limit disclosure to employees and contractors with a need to know, and shall ensure such individuals are bound by confidentiality obligations no less restrictive than those contained herein.', 'contract'),
('DOC-011', 7, 'Return or destruction of materials: Upon written request or expiration of this Agreement, Receiving Party shall return or certify destruction of all Confidential Information within fifteen (15) business days.', 'contract'),
('DOC-011', 8, 'Remedies: Receiving Party acknowledges that breach may cause irreparable harm not adequately compensated by monetary damages. Disclosing Party shall be entitled to seek injunctive relief in addition to any other remedies available at law or in equity.', 'contract'),
('DOC-011', 9, 'Governing Law: State of California. Venue: San Diego County Superior Court or the United States District Court for the Southern District of California.', 'contract'),
('DOC-011', 10, 'Witnessed and executed:\nFor TechForward: Angela Morrison, VP BD, Date: 2024-05-01\nFor Quantum Dynamics: Raj Krishnamurthy, CTO, Date: 2024-05-01\nNotarized: Public Notary #4487291, San Diego County', 'contract'),

-- Document 12: Email (8 chunks)
('DOC-012', 1, 'From: compliance@insuranceco.com\nTo: data-team@insuranceco.com\nDate: 2024-06-10\nSubject: CCPA Data Deletion Request - Batch #447\n\nTeam,\n\nWe have received 23 verified data deletion requests that must be processed within 45 days per CCPA requirements.', 'email'),
('DOC-012', 2, 'High-priority deletions (identity verified via government ID):\n- Request #D-4471: Customer Angela Peters, angela.peters@yahoo.com, account #INS-8842156\n- Request #D-4472: Customer Raymond Liu, raymond.liu@hotmail.com, account #INS-9917432\n- Request #D-4473: Customer Nicole Stewart, n.stewart@protonmail.com, account #INS-7753891', 'email'),
('DOC-012', 3, 'Scope of deletion: All personal data across CUSTOMER_MASTER, POLICY_HISTORY, CLAIMS_DATA, COMMUNICATIONS_LOG, and MARKETING_PREFERENCES. Retain only anonymized aggregate data required for actuarial calculations per our retention schedule.', 'email'),
('DOC-012', 4, 'Exception: Claim #CLM-2024-0089 for Raymond Liu is currently in active litigation. Per legal hold memo from General Counsel Patricia Hoffman, all data related to this claim must be preserved until litigation concludes. Process deletion for all other tables.', 'email'),
('DOC-012', 5, 'Verification: Each request has been authenticated through our two-factor identity verification process. Government IDs and account verification are on file with the Privacy Team. No further verification needed before processing.', 'email'),
('DOC-012', 6, 'Processing deadline: July 25, 2024. Please confirm completion to compliance@insuranceco.com and cc privacy officer Karen Wu (karen.wu@insuranceco.com). Deletion certificates must be generated for each request.', 'email'),
('DOC-012', 7, 'Reminder: After deletion, update our suppression list to ensure these individuals are not re-acquired through marketing campaigns or third-party data enrichment. The suppression list retains only hashed email addresses for matching purposes.', 'email'),
('DOC-012', 8, 'For questions about legal holds or exceptions, contact Associate General Counsel Mark Davidson at mark.davidson@insuranceco.com or ext. 3318. For technical issues with the deletion pipeline, contact DBA team lead Priya Sharma at priya.sharma@insuranceco.com.', 'email'),

-- Document 13: Support ticket (8 chunks)
('DOC-013', 1, 'Ticket #SUP-33120 | Priority: Medium | Created: 2024-07-22 11:30 CST\nReporter: Carlos Mendez (carlos.mendez@eduplatform.org)\nOrganization: National Learning Platform\nSubject: Student records appearing in analytics exports', 'support_ticket'),
('DOC-013', 2, 'Description: Our weekly analytics export job is including student PII (names, email addresses, student IDs) in the CSV files delivered to our research partners. These partners should only receive anonymized or pseudonymized data per our FERPA compliance requirements.', 'support_ticket'),
('DOC-013', 3, 'Example from last export (file: analytics_export_20240721.csv):\nRow 4412: student_id=STU-882941, name="Ashley Washington", email="a.washington@university.edu", gpa=3.74, enrollment_status="active"\nThis should show: student_id=ANON-4412, name=NULL, email=NULL, gpa=3.74, enrollment_status="active"', 'support_ticket'),
('DOC-013', 4, 'The export pipeline runs as a scheduled task every Sunday at 2:00 AM CST. It queries the STUDENT_ANALYTICS view which is supposed to apply masking policies. However, the task runs under SERVICE_ACCOUNT_EXPORTS role which appears to bypass masking.', 'support_ticket'),
('DOC-013', 5, 'Affected students: Approximately 45,000 records exported weekly to 3 research partner organizations. This has potentially been occurring for the past 6 weeks (since we migrated the export job to the new service account).', 'support_ticket'),
('DOC-013', 6, 'We need: 1) Immediate fix to mask student PII in exports. 2) Confirmation of which exports contained unmasked data. 3) Guidance on our notification obligations under FERPA. Our FERPA compliance officer is Janet Morrison, janet.morrison@eduplatform.org.', 'support_ticket'),
('DOC-013', 7, 'Research partners affected:\n- National Education Research Institute (contact: Dr. Harold Simmons, h.simmons@neri.org)\n- State University Analytics Lab (contact: Prof. Diana Kowalski, d.kowalski@stateuniv.edu)\n- EdTech Insights Foundation (contact: Marcus Chen, m.chen@edtechinsights.org)', 'support_ticket'),
('DOC-013', 8, 'Resolution: Applied masking policy to SERVICE_ACCOUNT_EXPORTS role. Verified next export contains only anonymized data. Notified all research partners of potential exposure and initiated FERPA incident review process with compliance officer Janet Morrison.', 'support_ticket'),

-- Document 14: Medical note (10 chunks)
('DOC-014', 1, 'THERAPY SESSION NOTES — CONFIDENTIAL\nProvider: Dr. Linda Park, PhD, Licensed Clinical Psychologist\nLicense #: PSY-CA-28841\nPractice: Mindful Horizons Therapy, 1200 Wilshire Blvd, Suite 420, Los Angeles, CA 90017', 'medical_note'),
('DOC-014', 2, 'Patient: Daniel Reeves, DOB: 03/27/1991, Age: 33\nSession Date: 2024-04-18, Session #14\nSession Type: Individual therapy, 50 minutes\nDiagnosis: Generalized Anxiety Disorder (F41.1), Major Depressive Disorder, recurrent, moderate (F33.1)', 'medical_note'),
('DOC-014', 3, 'Presenting concerns this session: Patient reports increased work-related anxiety following notification of upcoming layoffs at his employer. Sleep disturbance has worsened (averaging 4-5 hours, down from 6-7 at last session). Appetite decreased.', 'medical_note'),
('DOC-014', 4, 'Interventions: Cognitive restructuring focused on catastrophic thinking patterns ("I will definitely lose my job and won''t be able to pay rent"). Identified 3 cognitive distortions: fortune telling, catastrophizing, and all-or-nothing thinking.', 'medical_note'),
('DOC-014', 5, 'Homework assigned: Daily thought record focusing on work-related anxious thoughts. Practice 4-7-8 breathing technique before bed. Continue mindfulness meditation app (10 min/day). Schedule one enjoyable activity per day (behavioral activation).', 'medical_note'),
('DOC-014', 6, 'Safety assessment: Denies suicidal ideation, self-harm urges, or homicidal ideation. Has social support (partner Chris, close friend group). Maintains engagement with hobbies (running, cooking). No substance use concerns.', 'medical_note'),
('DOC-014', 7, 'Treatment progress: PHQ-9 score decreased from 16 (moderately severe) at intake to 12 (moderate) at current assessment. GAD-7 remains elevated at 14 (moderate-severe). Patient demonstrates good insight and engagement with CBT techniques.', 'medical_note'),
('DOC-014', 8, 'Coordination of care: Discussed referral to psychiatrist for medication evaluation given persistent sleep disturbance. Patient agreed. Referral sent to Dr. Michael Ashford, MD, Psychiatry, (310) 555-0891. Patient''s PCP Dr. Yuki Tanaka has been informed.', 'medical_note'),
('DOC-014', 9, 'Next session: 2024-04-25 at 3:00 PM. Plan to continue CBT for anxiety with focus on behavioral experiments around workplace uncertainty. Will review thought records and sleep hygiene progress.', 'medical_note'),
('DOC-014', 10, 'Note: Patient authorized release of information to Dr. Ashford (psychiatry referral) and Dr. Tanaka (PCP) on file. Emergency contact: Chris Martinez (partner), (310) 555-0724. Crisis line provided: 988 Suicide & Crisis Lifeline.', 'medical_note'),

-- Document 15: Financial report (8 chunks)
('DOC-015', 1, 'INVESTOR UPDATE — Series C Fundraising\nCompany: DataPipeline Technologies Inc.\nCEO: Andrew Park\nDate: 2024-04-30\nDistribution: Board of Directors, Lead Investors\nClassification: STRICTLY CONFIDENTIAL', 'financial_report'),
('DOC-015', 2, 'Fundraising status: Series C round targeting $75M at $450M pre-money valuation. Lead investor: Sequoia Capital (partner: Michelle Zhao, michelle.zhao@sequoiacap.com). Term sheet signed April 15, 2024. Expected close: May 31, 2024.', 'financial_report'),
('DOC-015', 3, 'Use of proceeds: 40% R&D expansion (target: 50 new engineers), 30% go-to-market (expand to EMEA/APAC), 20% infrastructure (multi-cloud support), 10% working capital reserve. 18-month runway at planned burn rate of $4.2M/month.', 'financial_report'),
('DOC-015', 4, 'Key metrics: ARR of $38M (growing 85% YoY). Net dollar retention: 145%. Gross margin: 78%. Customer count: 340 (up from 180 at Series B). Average contract value: $112K. Payback period: 14 months. Magic number: 1.3x.', 'financial_report'),
('DOC-015', 5, 'Cap table summary post-close: Founders retain 28% (Andrew Park 18%, CTO Sarah Lin 10%). Employee pool: 12%. Series A (Accel Partners): 15%. Series B (Andreessen Horowitz): 20%. Series C (Sequoia-led): 17%. Angels/advisors: 8%.', 'financial_report'),
('DOC-015', 6, 'Material risks disclosed to investors: (1) Customer concentration — top 5 customers represent 32% of ARR. (2) Key person dependency on CTO Sarah Lin for core platform architecture. (3) Pending patent dispute with DataFlow Corp (Case #2024-CV-01182, Northern District of California).', 'financial_report'),
('DOC-015', 7, 'Board composition post-close: Andrew Park (CEO, Chair), Sarah Lin (CTO), Michelle Zhao (Sequoia), David Kim (Accel), Jennifer Richards (a16z), one independent director TBD. Observer seats: two additional investor representatives.', 'financial_report'),
('DOC-015', 8, 'Legal counsel: Wilson Sonsini (partner: Robert Chang, robert.chang@wsgr.com). Auditor: Ernst & Young. Transfer agent: Carta. Next board meeting: June 15, 2024, 10:00 AM Pacific, in person at Sequoia offices, Menlo Park.', 'financial_report'),

-- Document 16: Email (10 chunks)
('DOC-016', 1, 'From: payroll@techstartup.io\nTo: all-employees@techstartup.io\nDate: 2024-01-29\nSubject: Important: W-2 Distribution and Tax Information\n\nHello everyone,\n\nYour 2023 W-2 forms are now available in the HR portal.', 'email'),
('DOC-016', 2, 'To access your W-2:\n1. Log in to hr.techstartup.io/payroll\n2. Navigate to Tax Documents > 2023\n3. Download or print your W-2\n\nIf you cannot access the portal, contact payroll manager Steven Rodriguez at steven.rodriguez@techstartup.io or ext. 2240.', 'email'),
('DOC-016', 3, 'Important notes:\n- If you had a name change during 2023, verify that your W-2 reflects your current legal name and Social Security number. Contact HR immediately if there is a discrepancy.\n- Employees in multiple states will receive separate state W-2 forms.', 'email'),
('DOC-016', 4, 'For employees who relocated during 2023:\n- California employees who moved to Texas: Your CA wages are reported through your last CA work date. TX has no state income tax.\n- NY employees who moved to FL: Similar split applies. Contact payroll with questions.', 'email'),
('DOC-016', 5, 'Stock compensation: RSU vestings and ESPP purchases are reflected in Box 12 (Code V for RSUs). Your cost basis information is available separately through our equity management platform (Carta). Carta support: equity@techstartup.io.', 'email'),
('DOC-016', 6, 'Deadline reminders:\n- Federal tax filing deadline: April 15, 2024\n- State deadlines vary (CA: April 15, NY: April 15, TX: N/A)\n- Extension requests (Form 4868) due by April 15\n\nThe company does not provide individual tax advice. Consult your tax professional.', 'email'),
('DOC-016', 7, 'Common W-2 questions:\nQ: Why is Box 1 different from my annual salary?\nA: Box 1 reflects taxable wages after pre-tax deductions (401k, health insurance premiums, FSA/HSA contributions, commuter benefits).', 'email'),
('DOC-016', 8, 'Q: I participated in the ESPP. Where do I see this?\nA: ESPP discount is included in Box 1 as ordinary income. The purchase details (shares, price, dates) are in your Carta account. You will also receive a Form 3922 by mid-February.', 'email'),
('DOC-016', 9, 'Physical copies: If you elected paper delivery, your W-2 will be mailed to your address on file by January 31. Mailing address updates must be submitted to payroll before January 30 to ensure correct delivery.', 'email'),
('DOC-016', 10, 'If you believe your W-2 contains an error, submit a correction request through the HR portal within 30 days. Corrected W-2c forms will be issued within 2 weeks of verification. Questions? Email payroll@techstartup.io or call (415) 555-0188.', 'email'),

-- Document 17: Support ticket (10 chunks)
('DOC-017', 1, 'Ticket #SUP-34889 | Priority: High | Created: 2024-08-05 15:45 PST\nReporter: Olivia Martinez (olivia.martinez@fintechco.com)\nOrganization: FinTech Innovations Corp\nSubject: Need to implement PII redaction for regulatory audit', 'support_ticket'),
('DOC-017', 2, 'Background: We are undergoing an OCC regulatory examination and need to provide auditors with access to our transaction logs. However, the logs contain customer names, account numbers, and addresses that auditors do not need to see for their specific review scope.', 'support_ticket'),
('DOC-017', 3, 'Current data sample from TRANSACTION_LOGS:\n"Transfer of $5,000 from John Martinez (Acct: 4471-8829-001) to Maria Santos (Acct: 4471-5567-003) initiated at 14:22 EST. Sender address: 445 Park Avenue, Apt 12B, New York, NY 10022."', 'support_ticket'),
('DOC-017', 4, 'Desired output for auditors:\n"Transfer of $5,000 from [PERSON_1] (Acct: [ACCOUNT_1]) to [PERSON_2] (Acct: [ACCOUNT_2]) initiated at 14:22 EST. Sender address: [ADDRESS_1]."\n\nWe need the transaction amounts, timestamps, and patterns preserved while redacting identifiers.', 'support_ticket'),
('DOC-017', 5, 'Volume: 2.8 million transaction log entries over the 3-year audit window. Auditors need access by August 19 (2 weeks). We need a solution that can process this volume and be re-run as new transactions are logged during the audit period.', 'support_ticket'),
('DOC-017', 6, 'Requirements:\n1. Consistent entity labeling (same person gets same label within a document)\n2. Preserve all non-PII content exactly\n3. Process 2.8M rows within reasonable timeframe\n4. Auditable — auditors need confidence that redaction is complete\n5. Reversible for authorized compliance staff if needed', 'support_ticket'),
('DOC-017', 7, 'Our compliance team has reviewed Snowflake AI_REDACT but has concerns about the fixed category set. We specifically need to redact internal account numbers (format: 4-4-3 digit pattern) which is proprietary and not a standard PII category.', 'support_ticket'),
('DOC-017', 8, 'Technical contact: Senior Data Engineer Hassan Ahmed, hassan.ahmed@fintechco.com, (646) 555-0933. He has ACCOUNTADMIN access and can implement the solution. Budget approved for additional compute costs.', 'support_ticket'),
('DOC-017', 9, 'Compliance officer: Director of Regulatory Affairs Julia Chen, julia.chen@fintechco.com. She will need to sign off on the redaction approach before we share data with OCC examiners. Legal counsel: external firm Baker McKenzie (partner: Thomas Reid).', 'support_ticket'),
('DOC-017', 10, 'Additional context: We previously used a Python script with spaCy NER running on EC2 for similar redaction tasks. It took 3 days to process and had a 12% miss rate on financial account numbers. We need something more reliable and faster that keeps data in Snowflake.', 'support_ticket'),

-- Document 18: Medical note (10 chunks)
('DOC-018', 1, 'REFERRAL LETTER\nFrom: Dr. Amanda Chen, MD — Internal Medicine\nTo: Dr. Robert Yamazaki, MD — Gastroenterology\nDate: 2024-05-20\nRe: Patient consultation request', 'medical_note'),
('DOC-018', 2, 'Patient: Jennifer Brooks, DOB: 06/18/1977, Age: 46\nMRN: PMG-7741290\nInsurance: Aetna PPO, Group #: AET-554-1092, Member ID: W884712904\nPhone: (425) 555-0318, Email: j.brooks47@gmail.com', 'medical_note'),
('DOC-018', 3, 'Reason for referral: Persistent upper abdominal pain and dyspepsia for 8 weeks despite empiric PPI therapy (omeprazole 40mg daily x 6 weeks). H. pylori stool antigen negative. Symptoms include postprandial pain, early satiety, and 7-lb unintentional weight loss.', 'medical_note'),
('DOC-018', 4, 'Relevant history: No prior GI diagnoses. Family history significant for maternal grandmother with gastric cancer (age 68) and father with colon polyps (age 55). No NSAID use. Social: occasional alcohol (2-3 drinks/week), never smoker.', 'medical_note'),
('DOC-018', 5, 'Recent labs (2024-05-15): CBC within normal limits. CMP unremarkable except mildly elevated alkaline phosphatase (128 U/L, ref 44-121). Lipase normal. CEA normal. Iron studies normal. Stool guaiac negative x3.', 'medical_note'),
('DOC-018', 6, 'Assessment: Given persistent symptoms despite adequate PPI trial, family history of GI malignancy, unintentional weight loss, and elevated alk phos, recommend upper endoscopy with biopsies. Would also consider abdominal CT or MRCP if EGD unrevealing.', 'medical_note'),
('DOC-018', 7, 'Current medications: Omeprazole 40mg daily, levothyroxine 75mcg daily, sertraline 50mg daily. Allergies: Sulfa drugs (rash), shellfish (anaphylaxis — patient carries EpiPen).', 'medical_note'),
('DOC-018', 8, 'Please contact patient directly for scheduling. She prefers morning appointments and has availability Tuesdays and Thursdays. Emergency contact: Michael Brooks (husband), (425) 555-0322.', 'medical_note'),
('DOC-018', 9, 'Thank you for seeing this patient on an expedited basis given the concerning features. Please send consultation notes to my office at 9800 Medical Center Drive, Suite 220, Bellevue, WA 98004, fax: (425) 555-0399.', 'medical_note'),
('DOC-018', 10, 'Electronically signed: Dr. Amanda Chen, MD\nNPI: 1987654321\nPacific Medical Group\n9800 Medical Center Drive, Suite 220\nBellevue, WA 98004\nPhone: (425) 555-0300', 'medical_note'),

-- Document 19: Contract (10 chunks)
('DOC-019', 1, 'EMPLOYMENT AGREEMENT\nEmployer: Horizon Software Solutions Inc.\nEmployee: Priya Kapoor\nPosition: Chief Technology Officer\nStart Date: March 18, 2024\nCompensation: Base salary $385,000 annually', 'contract'),
('DOC-019', 2, 'Employee contact information:\nPriya Kapoor\n1847 Lakeview Drive, Apartment 4C\nSeattle, WA 98109\nPersonal email: priya.kapoor.personal@gmail.com\nPhone: (206) 555-0471\nSSN: provided on separate Form W-4', 'contract'),
('DOC-019', 3, 'Equity compensation: 200,000 stock options at strike price of $12.40/share (FMV as of grant date). Vesting: 25% cliff at 12 months, then monthly vesting over remaining 36 months. Acceleration on change of control (double-trigger).', 'contract'),
('DOC-019', 4, 'Annual bonus: Target bonus of 40% of base salary ($154,000 at target), based on company performance (60% weight) and individual objectives (40% weight). Paid quarterly with true-up in Q1 of following fiscal year.', 'contract'),
('DOC-019', 5, 'Benefits: Executive health plan (no deductible, no co-pay), dental, vision, life insurance (3x salary), LTD (60% of salary). 401(k) with 6% match. Additional $10,000 annual wellness stipend and $5,000 professional development budget.', 'contract'),
('DOC-019', 6, 'Non-compete: Employee agrees to a 12-month non-competition period following termination in the Pacific Northwest region (WA, OR) for any company that directly competes with Employer in the enterprise middleware market.', 'contract'),
('DOC-019', 7, 'Severance: In the event of termination without cause, Employee shall receive 12 months base salary continuation, prorated bonus for the current year, and 12 months accelerated vesting. COBRA coverage paid for 18 months.', 'contract'),
('DOC-019', 8, 'Reporting structure: Employee reports directly to CEO Jonathan Drake (jonathan.drake@horizonsw.com). Employee shall have direct reports including VP Engineering, VP Product, and Director of Security.', 'contract'),
('DOC-019', 9, 'Invention assignment: All work product, inventions, and intellectual property created during employment or using company resources are the sole property of Employer. Employee represents no prior inventions conflict with this assignment.', 'contract'),
('DOC-019', 10, 'Signatures:\nEmployer: Jonathan Drake, CEO, Horizon Software Solutions Inc., Date: 2024-03-10\nEmployee: Priya Kapoor, Date: 2024-03-12\nWitness: HR Director Compliance, Laura Bennett, Date: 2024-03-12', 'contract'),

-- Document 20: Financial report (12 chunks)
('DOC-020', 1, 'BOARD MEETING MINUTES — CONFIDENTIAL\nCompany: Pinnacle Data Systems Inc.\nDate: 2024-06-15, 9:00 AM - 12:30 PM Pacific\nLocation: Boardroom A, 500 Howard Street, San Francisco, CA 94105\nChair: Elizabeth Warren (Independent Director)', 'financial_report'),
('DOC-020', 2, 'Attendees: Elizabeth Warren (Chair), CEO Marcus Thompson, CFO Diana Patel, COO James Richardson, General Counsel Nina Volkov, Independent Directors: Robert Blackwell, Michelle Tanaka, Ahmed Hassan. Secretary: VP Legal Affairs, Christine Park.', 'financial_report'),
('DOC-020', 3, 'Agenda Item 1: Q2 Financial Results (presented by CFO Diana Patel)\n- Revenue: $52.3M (vs. $48.1M plan, 8.7% beat)\n- EBITDA: $12.1M (23.1% margin, up from 19.8% Q1)\n- Free cash flow: $8.4M (first positive FCF quarter)\n- Customer count: 892 (net add of 47 in Q2)', 'financial_report'),
('DOC-020', 4, 'Agenda Item 2: Strategic Partnership Discussion\n- CEO Marcus Thompson presented opportunity for strategic partnership with major cloud provider (codename: Project Atlas)\n- Potential deal value: $200-250M over 5 years\n- Requires exclusive technology integration commitment for 3 years\n- Board requested detailed financial model by next meeting', 'financial_report'),
('DOC-020', 5, 'Agenda Item 3: Executive Compensation Review\n- Compensation committee chair Robert Blackwell presented annual review\n- CEO total comp: $1.2M base + $2.4M equity + $960K target bonus = $4.56M total\n- CFO total comp: $650K base + $1.3M equity + $455K target bonus = $2.405M total\n- All within 50th-75th percentile of peer group benchmarks', 'financial_report'),
('DOC-020', 6, 'Agenda Item 4: Cybersecurity Incident Report (presented by CISO David Nakamura)\n- Phishing attempt targeting 3 C-level executives in May\n- No data exfiltration confirmed\n- Recommended: mandatory hardware security keys for all executives\n- Board approved $180K security enhancement budget', 'financial_report'),
('DOC-020', 7, 'Agenda Item 5: M&A Pipeline Update (presented by VP Corp Dev, Sarah Kim)\n- Target A (codename: Sapphire): Analytics startup, $45M valuation, 40 engineers, strong Snowflake integration\n- Target B (codename: Emerald): Data quality platform, $28M valuation, strategic IP portfolio\n- Board authorized due diligence on Target A, approved LOI budget of $50-55M', 'financial_report'),
('DOC-020', 8, 'Agenda Item 6: IPO Readiness Assessment (presented by General Counsel Nina Volkov)\n- SOX compliance: 85% complete, on track for Q4 certification\n- Financial restatement risk: low (clean audit history)\n- Insider trading policy: updated, all executives compliant\n- Selected underwriters: Goldman Sachs (lead), Morgan Stanley (co-lead)\n- Target filing: Q1 2025, market conditions permitting', 'financial_report'),
('DOC-020', 9, 'Closed Session: Board discussed CEO performance review without management present. Unanimous vote to extend CEO contract through 2027 with revised equity package. Details in sealed minutes filed with corporate secretary.', 'financial_report'),
('DOC-020', 10, 'Action Items:\n1. CFO to present Project Atlas financial model by July 15 (owner: Diana Patel)\n2. CISO to implement hardware key rollout by August 1 (owner: David Nakamura)\n3. VP Corp Dev to complete Target A due diligence by July 30 (owner: Sarah Kim)\n4. GC to finalize IPO timeline with underwriters (owner: Nina Volkov)', 'financial_report'),
('DOC-020', 11, 'Next Meeting: July 20, 2024, 9:00 AM Pacific. Agenda: Project Atlas update, Q2 earnings prep, Target A DD findings, IPO timeline review.', 'financial_report'),
('DOC-020', 12, 'Minutes approved by: Elizabeth Warren, Board Chair\nRecorded by: Christine Park, VP Legal Affairs\nDistribution: Board members only via secure board portal (Diligent Boards)\nRetention: Permanent corporate record per Delaware General Corporation Law §142', 'financial_report');


-- ─────────────────────────────────────────────────────────────────────────────
-- 5. REDACT_PII UDF
-- ─────────────────────────────────────────────────────────────────────────────
-- Takes original text and a JSON object containing extracted PII entities.
-- Returns the text with PII replaced by typed labels like [NAME REDACTED].
-- Sorts replacements by phrase length (longest first) to avoid partial matches.

CREATE OR REPLACE FUNCTION REDACT_PII(chunk VARCHAR, pii_entities VARIANT)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
HANDLER = 'redact_pii'
AS
$$
def redact_pii(chunk, pii_entities):
    if chunk is None or pii_entities is None:
        return chunk
    if isinstance(pii_entities, str):
        import json
        pii_entities = json.loads(pii_entities)
    items = pii_entities.get('redacted_items', [])
    if not items:
        return chunk
    result = chunk
    # Sort by phrase length descending to avoid partial replacement collisions
    # e.g. replace "John Smith" before "John"
    for item in sorted(items, key=lambda x: len(x.get('phrase', '')), reverse=True):
        phrase = item.get('phrase', '')
        field_type = item.get('field_type', 'PII').upper()
        if phrase:
            result = result.replace(phrase, f'[{field_type} REDACTED]')
    return result
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 6. PII_ENTITY_CACHE TABLE
-- ─────────────────────────────────────────────────────────────────────────────
-- Pre-computed cache for PII entities extracted at ingestion time.
-- Populated during the lab exercises. Enables zero-LLM query-time redaction.

CREATE OR REPLACE TABLE PII_ENTITY_CACHE (
    DOC_ID         VARCHAR,
    CHUNK_INDEX    NUMBER,
    PII_ENTITIES   VARIANT,
    CONTENT_HASH   VARCHAR,
    EXTRACTED_AT   TIMESTAMP_NTZ
);


-- ─────────────────────────────────────────────────────────────────────────────
-- 7. VERIFICATION
-- ─────────────────────────────────────────────────────────────────────────────

-- Confirm row counts
SELECT 'DOCUMENT_CHUNKS' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM DOCUMENT_CHUNKS
UNION ALL
SELECT 'PII_ENTITY_CACHE', COUNT(*) FROM PII_ENTITY_CACHE;

-- Verify document distribution
SELECT DOC_TYPE, COUNT(DISTINCT DOC_ID) AS NUM_DOCS, COUNT(*) AS NUM_CHUNKS
FROM DOCUMENT_CHUNKS
GROUP BY DOC_TYPE
ORDER BY NUM_DOCS DESC;

-- Sample rows with PII
SELECT DOC_ID, CHUNK_INDEX, DOC_TYPE, LEFT(CHUNK_TEXT, 100) AS PREVIEW
FROM DOCUMENT_CHUNKS
WHERE CHUNK_INDEX = 1
ORDER BY DOC_ID
LIMIT 10;

-- Test UDF with sample data
SELECT REDACT_PII(
    'Contact John Smith at john.smith@example.com or (555) 123-4567.',
    PARSE_JSON('{"redacted_items": [{"phrase": "John Smith", "field_type": "NAME"}, {"phrase": "john.smith@example.com", "field_type": "EMAIL"}, {"phrase": "(555) 123-4567", "field_type": "PHONE"}]}')
) AS REDACTED_SAMPLE;

-- ─────────────────────────────────────────────────────────────────────────────
-- SETUP COMPLETE
-- ─────────────────────────────────────────────────────────────────────────────
-- Objects created:
--   - Database: PII_REDACTION_DEMO
--   - Schema: REDACTION
--   - Warehouse: PII_REDACTION_WH (MEDIUM, auto-suspend 120s)
--   - Table: DOCUMENT_CHUNKS (200 chunks across 20 documents)
--   - Function: REDACT_PII (Python UDF for typed PII replacement)
--   - Table: PII_ENTITY_CACHE (empty, populated during lab)
--
-- Next step: Open the lab notebook (pii-redaction-lab.ipynb) to begin.
-- ─────────────────────────────────────────────────────────────────────────────
