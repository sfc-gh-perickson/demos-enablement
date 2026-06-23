# Speaker Notes: Data Labeling on Snowflake — Label Studio on SPCS

## Account Context Summary

This presentation is an internal enablement session covering how to deploy Label Studio on Snowpark Container Services (SPCS) with a Snowflake Postgres backend for annotation storage. It targets SEs, AEs, and solution architects. Label Studio on SPCS is NOT a Snowflake product — it is an open-source deployment pattern that demonstrates SPCS's flexibility as a general-purpose container platform beyond ML inference. The core value proposition is data governance: labeled data never leaves the Snowflake security perimeter, eliminating egress costs and compliance risk while still providing a best-in-class labeling UX.

The competitive differentiator is clear: every alternative either requires data to leave the customer's environment (Labelbox, Scale AI, V7) or locks data into a specific cloud provider's storage layer (SageMaker Ground Truth → S3, Vertex AI Data Labeling → GCS). Label Studio on SPCS keeps data in Snowflake, governed by existing RBAC, with zero additional security review required. SPCS is GA, Snowflake Postgres is GA, and Label Studio is open-source under Apache 2.0 (maintained by HumanSignal). This is a production-ready pattern today.

---

## Slide 1: Title — "Data Labeling on Snowflake: Label Studio on SPCS"

**Talking Points:**
- Frame the session: "We're going to walk through how to run a full data labeling platform on Snowflake using SPCS and Snowflake Postgres — zero egress, full governance, production-ready."
- This is a pattern/reference architecture, not a Snowflake product. It demonstrates SPCS as a general-purpose container runtime.
- Set expectations: we'll cover architecture, deployment, security, and production considerations. The lab guide has all the hands-on steps.
- Key audience question to plant: "How are your customers handling data labeling today? Are they sending sensitive data to SaaS tools?"

**Internal Context:**
- SPCS is GA. Snowflake Postgres is GA. Label Studio is open-source (HumanSignal maintains it commercially as Label Studio Enterprise, but the open-source version is fully functional for this pattern).
- This positions Snowflake as a complete ML platform — not just storage/compute for training, but the entire lifecycle from labeling through inference.
- The "no egress" story resonates strongly with regulated industries: financial services, healthcare, government, and any customer with strict data residency requirements.

**References:**
- https://docs.snowflake.com/en/developer-guide/snowpark-container-services/overview
- https://docs.snowflake.com/en/sql-reference/sql/create-postgres-instance
- https://labelstud.io/guide/

---

## Slide 2: The Data Labeling Challenge

**Talking Points:**
- Start with the pain: "Every supervised ML model needs labeled data. The quality of that labeled data is the single biggest determinant of model quality — ahead of architecture, hyperparameters, or compute budget."
- Walk through each challenge:
  - Cost: professional labeling services charge $1-$10+ per label. A 10K image dataset for object detection can cost $50K-$100K.
  - Speed: weeks of annotator time, iterative review cycles, re-labeling when guidelines change.
  - Collaboration: inter-annotator agreement, consensus labeling, reviewer workflows. Without tooling, this is managed in spreadsheets.
  - Security: "If your data contains PII, patient records, financial documents, or proprietary IP — can you send it to a SaaS labeling platform? Most security teams say no."
- The security angle is the key opening for Snowflake's value prop. Let the audience feel the pain before presenting the solution.

**Internal Context:**
- The security objection is real and common. Many enterprise ML projects stall at the labeling stage because the security team won't approve data export to labeling SaaS tools.
- Common workaround customers use today: anonymize/redact data before export (lossy, expensive), self-host Label Studio on EC2/GKE (operational burden, no Snowflake integration), or use Snowflake-external storage mounted into a VM (data copies, drift).
- This slide sets up the "why SPCS" answer — let the audience arrive at the conclusion themselves.

**References:**
- https://labelstud.io/guide/
- https://docs.snowflake.com/en/developer-guide/snowpark-container-services/overview

---

## Slide 3: Why Label Studio on SPCS

**Talking Points:**
- Now deliver the solution: "What if you could run the labeling tool inside Snowflake, next to the data, with full governance — and the annotators just see a web browser?"
- Walk through each value prop:
  - Zero egress: data is read from stages mounted into the container. Never copied out.
  - Governed by RBAC: the same roles that control table access control stage access and compute pool access.
  - Elastic compute: SPCS compute pools auto-suspend. Pay for labeling sprints, not idle infrastructure.
  - Native stages: no S3 bucket to configure, no cross-account IAM roles. Just `@my_stage/images/`.
  - Open-source: no per-seat licensing. Apache 2.0. Full control over configuration, extensions, and ML backends.
  - Single platform: the same Snowflake account hosts the raw data, the labeling tool, the annotations, and eventually the trained model.
- If asked "why not Label Studio Enterprise?": The open-source version handles most use cases. Enterprise adds SSO, SCIM, advanced review workflows, and support. Customers can upgrade later if needed — the architecture is the same.

**Internal Context:**
- The "data never leaves" story is the #1 differentiator. Every competitor requires data to be somewhere else.
- "No vendor lock-in" resonates with platform engineering teams who've been burned by labeling tool migrations. Label Studio uses standard JSON annotation formats that export cleanly.
- SPCS positioning: this is NOT a Snowflake labeling product. It's "look what SPCS can do." This positions SPCS as genuinely general-purpose — web apps, internal tools, ML workflows, not just model serving.
- If the audience asks about Snowflake Cortex Fine-Tuning: that's complementary. You label data with Label Studio, then use it to fine-tune via Cortex. Full lifecycle.

**References:**
- https://docs.snowflake.com/en/developer-guide/snowpark-container-services/overview
- https://docs.snowflake.com/en/developer-guide/snowpark-container-services/specification-reference
- https://labelstud.io/guide/install

---

## Slide 4: Architecture

**Talking Points:**
- Walk through the diagram top-to-bottom:
  - SPCS Compute Pool runs the Label Studio container. This is standard Docker — the same image you'd run locally or on K8s.
  - Snowflake Postgres stores all Label Studio metadata: projects, tasks, annotations, user accounts. This replaces the SQLite default or external PostgreSQL that you'd normally provision.
  - Stage Volumes mount internal stages into the container's filesystem. Label Studio reads images/documents/audio directly from the stage path.
  - Public Endpoint exposes the web UI via HTTPS. OAuth authentication ensures only authorized Snowflake users can access it.
- Emphasize: "There are only four Snowflake objects to create beyond normal RBAC setup: a compute pool, an image repository, a Postgres instance, and a service. That's it."
- The Postgres role is critical: Label Studio needs a PostgreSQL-compatible database. Snowflake Postgres provides exactly this — wire-compatible, managed, zero-ops.

**Internal Context:**
- Architecture simplicity is a selling point. Compare to self-hosting on EC2: you'd need an EC2 instance, an RDS PostgreSQL instance, an S3 bucket, IAM roles, a load balancer, ACM certificates, security groups, and CloudWatch monitoring. Here it's four Snowflake objects.
- The stage volume mount is the key integration point. Without it, you'd need to copy data out of Snowflake — defeating the purpose. Stage volumes make the data accessible to the container as if it were a local filesystem.
- If asked about performance: stage volumes are backed by Snowflake's internal storage layer. Read throughput is excellent for serving files to a web UI. Not suitable for training workloads (use direct table access for that).

**References:**
- https://docs.snowflake.com/en/developer-guide/snowpark-container-services/specification-reference#volumes
- https://docs.snowflake.com/en/sql-reference/sql/create-postgres-instance
- https://docs.snowflake.com/en/developer-guide/snowpark-container-services/working-with-services

---

## Slide 5: SPCS Primitives Used

**Talking Points:**
- This slide grounds the architecture in specific SPCS objects. Walk through each:
  - Compute Pool: CPU_X64_S is sufficient for Label Studio (it's a web app, not a GPU workload). Multiple nodes for HA if needed.
  - Image Repository: private registry within Snowflake. `docker push` to it just like Docker Hub or ECR, but it's inside the account.
  - Stage Volumes: the magic that makes zero-egress work. Mount a stage as a path in the container spec YAML.
  - Public Endpoints: HTTPS with Snowflake OAuth. Annotators navigate to a URL in their browser — that's the full UX.
  - External Access Integration: opt-in outbound. Only needed if you want ML pre-labeling (calling an external model API) or webhook notifications.
  - Secrets: for the Postgres connection string. Never hardcode credentials in spec files.
- Key message: "Everything here is GA. No preview features, no flags to enable. You can deploy this in a production account today."

**Internal Context:**
- CPU_X64_S is the smallest instance family. Label Studio is lightweight — it's a Django web app. The bottleneck is annotator bandwidth, not compute.
- For customers who want GPU-accelerated pre-labeling (running a local model inside the container for auto-suggestions): they'd use a GPU compute pool for a sidecar ML backend service, not for Label Studio itself.
- External Access Integration is the one place where "data leaves Snowflake" could technically happen (outbound HTTP). Be clear: EAI is optional and fully auditable. If the customer doesn't enable it, the service is fully isolated.
- Common question: "Can I use an existing compute pool?" — Yes, if the instance family and resource limits are compatible. Label Studio doesn't need dedicated compute.

**References:**
- https://docs.snowflake.com/en/developer-guide/snowpark-container-services/working-with-compute-pool
- https://docs.snowflake.com/en/developer-guide/snowpark-container-services/working-with-registry-repository
- https://docs.snowflake.com/en/developer-guide/snowpark-container-services/specification-reference#endpoints
- https://docs.snowflake.com/en/developer-guide/snowpark-container-services/additional-considerations-services-jobs#network-egress

---

## Slide 6: Snowflake Postgres as Backend

**Talking Points:**
- Label Studio requires PostgreSQL for production use. The default SQLite backend doesn't support concurrent access or data durability at scale.
- Snowflake Postgres is the perfect fit: managed PostgreSQL, wire-compatible, zero DBA overhead.
- Walk through the options:
  - BURST_S: shared compute, burstable. Great for demos, labs, and single-annotator dev workflows.
  - STANDARD_M: dedicated compute, sustained throughput. Use for multi-annotator production. No burst credit exhaustion.
  - HIGH_AVAILABILITY=TRUE: synchronous replication, automatic failover. Zero annotation loss. Required for production where losing labeled data is unacceptable.
- PgBouncer is built-in: Label Studio opens many short-lived connections (one per annotator request). Connection pooling handles this automatically.
- Network policies: even though Postgres is inside the Snowflake perimeter, you can further restrict access to only the SPCS service's network identity.

**Internal Context:**
- Snowflake Postgres is GA. Key selling point: customers don't need to provision RDS, manage backups, or configure VPC peering. It's a CREATE statement.
- BURST_S vs STANDARD_M guidance: BURST_S is fine for up to ~5 concurrent annotators in a lab setting. For production teams (10+ annotators, sustained 8-hour labeling shifts), STANDARD_M avoids burst credit exhaustion and provides predictable performance.
- HIGH_AVAILABILITY is non-negotiable for production. Annotations are expensive to reproduce — losing them to a single-node failure is unacceptable. The cost delta is justified by the value of the labeled data.
- If asked about Postgres version: Snowflake Postgres runs PostgreSQL 16-compatible. Label Studio supports PG 12+, so compatibility is guaranteed.
- If asked "why not use Snowflake tables directly?": Label Studio's codebase is written against PostgreSQL with Django ORM. Changing the storage backend would require forking and maintaining Label Studio — impractical. Snowflake Postgres is the zero-friction path.

**References:**
- https://docs.snowflake.com/en/sql-reference/sql/create-postgres-instance
- https://docs.snowflake.com/en/user-guide/postgres/overview
- https://labelstud.io/guide/install#PostgreSQL-database

---

## Slide 7: Deployment Walkthrough

**Talking Points:**
- Walk through the six steps at a high level. The lab guide has the exact commands.
- Step 1 (Docker): Start FROM the official `heartexlabs/label-studio` image. Add `psycopg2-binary` if not already included. Optionally add custom ML backends.
- Step 2 (Push): Standard docker tag + push to the Snowflake image repo. Same workflow as any SPCS deployment.
- Step 3 (Postgres): One CREATE statement. Choose compute family and HA based on environment.
- Step 4 (Spec): The service spec YAML is where everything comes together — image reference, stage volume mounts, Postgres credentials from secrets, endpoint config, environment variables for Label Studio.
- Step 5 (Service): CREATE SERVICE on the compute pool with the spec. Label Studio runs Django migrations on first boot — the Postgres schema is auto-created.
- Step 6 (Access): Get the endpoint URL from SHOW ENDPOINTS. Navigate in browser. Create admin account on first access.
- Emphasize speed: "This is a 15-20 minute deployment. Most of that is the Docker build. The Snowflake objects come up in seconds."

**Internal Context:**
- Common issues during deployment:
  - Postgres credentials: must use secrets, not plain text in the spec. If credentials are wrong, Label Studio fails with a Django database connection error in the service logs.
  - Stage permissions: the service role must have READ (and optionally WRITE) on the stage being mounted.
  - Image not found: ensure the image repo and compute pool are in the same account and the service role has USAGE on the image repo.
- For the demo, pre-build the image and pre-create the Postgres instance to avoid waiting during the live session. The interesting part is the service creation and first access.
- Label Studio creates a superuser on first boot if LABEL_STUDIO_USERNAME and LABEL_STUDIO_PASSWORD environment variables are set. For OAuth-secured deployments, you may still want an internal admin account for initial project setup.

**References:**
- https://docs.snowflake.com/en/developer-guide/snowpark-container-services/working-with-registry-repository
- https://docs.snowflake.com/en/developer-guide/snowpark-container-services/specification-reference
- https://docs.snowflake.com/en/sql-reference/sql/create-service
- https://labelstud.io/guide/install#PostgreSQL-database

---

## Slide 8: Data Flow

**Talking Points:**
- Walk through the three phases: Ingestion → Labeling → Export.
- Ingestion: data originates in Snowflake tables or external stages. Copy/stage files into an internal stage that's mounted as a volume. For images, this is typically COPY INTO @stage from a table with file URLs, or direct PUT of files.
- Labeling: Label Studio reads files from the mounted stage path (e.g., `/data/images/`). Annotators see images/text/audio in the browser and create annotations. All annotations write to Postgres.
- Export: The recommended pattern is a **direct Postgres query** from Snowflake — a Python stored procedure with `psycopg2` connects to the Snowflake Postgres instance, queries Label Studio's internal annotation tables, and returns results as a Snowflake table. No intermediate files needed. This can also be automated with a Snowflake Task for scheduled syncs.
- Alternative export paths: Label Studio's built-in export (JSON, COCO, YOLO, VOC) to a stage, or pg_lake (requires STANDARD+ Postgres instance).
- Key point: "At no point does data leave the Snowflake account. The entire pipeline — storage, labeling UI, annotation DB, and export — runs inside Snowflake."
- Supported modalities: images (classification, detection, segmentation), text (NER, classification, sentiment), audio (transcription, classification), video (temporal annotation), and multi-modal.

**Internal Context:**
- The most common pattern: customers have images or documents in a Snowflake stage (loaded from their data lake or generated by a pipeline). They mount that stage into Label Studio and create a labeling project pointing to the mount path.
- Export back to Snowflake tables is the natural next step — this is where the labeled data becomes training data. The lab demonstrates a Python stored procedure that uses `psycopg2` + External Access Integration to query Label Studio's Postgres tables directly. No pg_lake required (pg_lake needs STANDARD+ instance). This works even with BURST_S.
- For production: wrap the export procedure in a Snowflake Task for automated periodic sync of new annotations.
- For text data: customers often export from Snowflake tables to JSONL files on a stage, then import those into Label Studio. The labeling interface shows the text, annotators add NER spans or classifications, and the annotations export as structured JSON.
- If asked about pre-signed URLs: Label Studio can serve files via pre-signed URLs from the stage volume. This is how images appear in the browser — the container generates a local file URL from the mount path.

**References:**
- https://docs.snowflake.com/en/developer-guide/snowpark-container-services/specification-reference#volumes
- https://labelstud.io/guide/storage
- https://labelstud.io/guide/export

---

## Slide 9: Security Model

**Talking Points:**
- Walk through each layer — this is defense-in-depth:
  - OAuth endpoints: Snowflake authenticates the user before they reach Label Studio. Only users with the service role can access the endpoint. This is different from Label Studio's internal auth — it's a gateway-level control.
  - RBAC: compute pool, service, stage, Postgres instance — all governed by Snowflake roles. Role hierarchy works as expected.
  - Network policies: Postgres access can be restricted to specific SPCS service network identities. Even if someone has credentials, they can't connect from outside the allowed network.
  - Secrets: Postgres connection strings stored as Snowflake secrets. Resolved at container runtime. Never visible in SHOW SERVICE, logs, or query history.
  - No egress: without EAI, the container has zero outbound network access. Data cannot leave even if the application is compromised.
  - Audit: all object access logged in ACCESS_HISTORY. SPCS service events logged. Postgres connections logged.
- Key message for security-sensitive customers: "The data never leaves the Snowflake perimeter. The labeling UI is served through an authenticated endpoint. The annotation database is inside Snowflake. There is no path for data exfiltration without explicit EAI configuration."

**Internal Context:**
- The OAuth endpoint is a significant security improvement over self-hosted Label Studio, where you'd need to manage your own auth (LDAP, SAML, or Label Studio's built-in user/password).
- For customers in regulated industries, the audit trail is critical: "Who labeled what, when, from where?" — answerable via Snowflake access history + Label Studio's internal audit log in Postgres.
- If asked about SOC 2 / HIPAA compliance: SPCS inherits Snowflake's compliance certifications. The data never leaves the Snowflake boundary. Label Studio's open-source code runs in your account — you control it fully.
- Competitive angle: SageMaker Ground Truth requires IAM roles, S3 bucket policies, and VPC endpoints. Labelbox requires data export to their cloud and a separate security review. Here, it's "same Snowflake governance you already have."

**References:**
- https://docs.snowflake.com/en/developer-guide/snowpark-container-services/specification-reference#endpoints
- https://docs.snowflake.com/en/developer-guide/snowpark-container-services/additional-considerations-services-jobs#network-egress
- https://docs.snowflake.com/en/sql-reference/sql/create-secret

---

## Slide 10: Production Considerations

**Talking Points:**
- This slide bridges from "lab demo" to "production deployment." Walk through each consideration:
  - HA Postgres: non-negotiable for production. Annotations are expensive to reproduce. HIGH_AVAILABILITY=TRUE gives you synchronous replication and automatic failover.
  - Compute family: STANDARD_M+ for Postgres in production. BURST_S is fine for demos but will throttle under sustained annotator load (8-hour labeling shifts).
  - ML pre-labeling: the biggest productivity multiplier. Use External Access Integration to call an ML model that pre-fills annotations. Annotators review and correct — 50-80% faster than labeling from scratch.
  - Team scaling: Label Studio supports multiple users, role-based access (annotator vs. reviewer vs. admin), inter-annotator agreement metrics, and consensus labeling workflows.
  - Automated pipelines: Snowflake Tasks to stage new data for labeling, trigger scheduled exports, and load completed annotations into training tables. Fully automated data flywheel.
  - Monitoring: SYSTEM$GET_SERVICE_STATUS for SPCS health. Postgres pg_stat views for database health. Snowflake alerts for automated notifications on failures.
- Close with: "This is a production-ready pattern today. The components are all GA. The only question is whether your customer has the labeling use case — and most ML teams do."

**Internal Context:**
- ML pre-labeling is the most advanced pattern and the strongest value-add. Example: customer has 100K images to label for object detection. They run a pre-trained model (via EAI to a model endpoint, or via a sidecar SPCS service) that generates initial bounding boxes. Annotators correct the 20% that are wrong. Cost drops from $500K to $100K.
- For team scaling, Label Studio Enterprise (paid) adds more sophisticated review workflows, SCIM/SSO, and annotator performance analytics. The open-source version supports basic multi-user with role assignment.
- Snowflake Tasks integration: CREATE TASK ... SCHEDULE = 'USING CRON 0 9 * * * America/Los_Angeles' ... CALL export_annotations_to_table(); — daily export of new annotations into a training table.
- If asked about backup: Snowflake Postgres supports Time Travel (point-in-time recovery). Combined with HA, this provides strong durability guarantees for annotation data.

**References:**
- https://docs.snowflake.com/en/sql-reference/sql/create-postgres-instance
- https://docs.snowflake.com/en/developer-guide/snowpark-container-services/additional-considerations-services-jobs#network-egress
- https://labelstud.io/guide/ml
- https://docs.snowflake.com/en/sql-reference/sql/create-task

---

## Slide 11: Demo / Q&A

**Talking Points:**
- Transition to live demo or pre-recorded walkthrough showing:
  1. The running Label Studio instance accessed via the public endpoint
  2. A labeling project with images loaded from a Snowflake stage
  3. The annotation workflow (create a few labels live)
  4. Export and verification that annotations are in Postgres
- Key links to share:
  - Lab guide: hands-on deployment instructions
  - Source code: Dockerfile, service spec, setup SQL
  - Label Studio docs: configuration reference, template library
- Closing message: "Label Studio on SPCS demonstrates that SPCS is a general-purpose container platform. If your customer has any containerized workload — internal tools, web apps, data labeling, model serving — SPCS can run it with Snowflake governance."
- Open for questions. Common Q&A topics:
  - "Can I run Label Studio Enterprise?" — Yes, same deployment pattern, different Docker image (commercial license required).
  - "What about GPU for real-time pre-labeling?" — Use a GPU compute pool for the ML backend sidecar service. Label Studio itself doesn't need GPU.
  - "How many annotators can it handle?" — Open-source handles 10-20 concurrent annotators on a single container. Scale horizontally with multiple replicas behind the endpoint for larger teams.

**Internal Context:**
- For the demo: pre-deploy everything before the session. The audience should see the working product, not watch a Docker build.
- Have a sample project with ~50 images pre-loaded and partially labeled. Show both the annotation UX and the Postgres data to prove annotations are stored inside Snowflake.
- If time allows, show the Snowflake side: SHOW SERVICES, SHOW ENDPOINTS, query the Postgres instance via psql to show the annotation tables. This reinforces the "it's all Snowflake" message.
- Competitive kill shots to have ready:
  - SageMaker Ground Truth: requires data in S3, separate AWS service, per-label pricing ($0.08-$0.80/label for their workforce), no Snowflake governance.
  - Vertex AI Data Labeling: requires GCS, separate GCP billing, limited labeling interface customization, no self-hosting option.
  - Labelbox: SaaS-only, data must leave your environment, $50+/seat/month pricing, enterprise features locked behind expensive tiers.
  - Scale AI: SaaS-only, premium pricing, data leaves your environment, primarily an outsourced workforce (not a self-serve tool).
  - Label Studio on SPCS: data stays in Snowflake, open-source (free), full customization, governed by existing policies, no per-seat or per-label costs beyond SPCS compute.

**References:**
- https://docs.snowflake.com/en/developer-guide/snowpark-container-services/overview
- https://docs.snowflake.com/en/sql-reference/sql/create-postgres-instance
- https://labelstud.io/guide/
- https://labelstud.io/templates/
