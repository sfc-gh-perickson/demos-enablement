# Label Studio on SPCS

[View Presentation](https://sfc-gh-perickson.github.io/demos-enablement/label-studio-spcs/presentations/label-studio-spcs.html)

Deploy Label Studio, an open-source data labeling platform, on Snowpark Container Services with Snowflake Postgres as the managed database backend.

## Audience

SEs, ML Engineers, Data Scientists, Platform Engineers

## Topics Covered

**Architecture:**
- Running containerized web applications on SPCS
- Snowflake Postgres as a managed application database
- Stage volumes for data access
- Public endpoints with OAuth authentication

**Operations:**
- Building and pushing container images to Snowflake image repositories
- SPCS service lifecycle management
- Postgres instance provisioning and networking
- External access integrations for outbound connectivity

**Data Labeling:**
- Creating annotation projects in Label Studio
- Importing data from Snowflake stages
- Exporting labeled data back to Snowflake tables
- Comparing human labels with Cortex AI functions

## Contents

| File | Description |
|------|-------------|
| [`presentations/label-studio-spcs.html`](https://sfc-gh-perickson.github.io/demos-enablement/label-studio-spcs/presentations/label-studio-spcs.html) | Slide deck (11 slides) |
| `presentations/label-studio-spcs-speaker-notes.md` | Speaker notes with internal context |
| `lab/setup.sql` | SQL setup script (database, Postgres instance, compute pool, sample data) |
| `lab/Dockerfile` | Container image for Label Studio |
| `lab/label-studio-spec.yaml` | SPCS service specification |
| `lab/label-studio-spcs-lab.ipynb` | Hands-on lab notebook (30-45 min) |

## Hands-On Lab

### Prerequisites

1. A Snowflake account with SPCS and Snowflake Postgres enabled
2. A role with CREATE DATABASE, CREATE WAREHOUSE, CREATE COMPUTE POOL, CREATE POSTGRES INSTANCE privileges
3. Docker installed locally (for building and pushing the container image)
4. Snowflake CLI installed (`snow` command)

### Setup

Run `label-studio-spcs/lab/setup.sql` to create:
- `LABEL_STUDIO_SPCS` database and `APP` schema
- `LABEL_STUDIO_WH` warehouse (XS)
- `LABEL_STUDIO_REPO` image repository
- `LABEL_STUDIO_PG` Snowflake Postgres instance (BURST_S)
- `LABEL_STUDIO_POOL` compute pool (CPU_X64_S)
- Internal stages for spec files and labeling data
- External access integration for outbound networking
- Sample labeling data (product reviews for sentiment analysis)

### Lab Sections

1. Verify prerequisites (compute pool, Postgres instance status)
2. Build and push the container image
3. Deploy the Label Studio service
4. Access the UI via public endpoint
5. Create a labeling project
6. Import data from Snowflake stages
7. Annotate data
8. Export annotations back to Snowflake
9. Compare human labels with Cortex AI classification

## Key Concepts

- **Snowpark Container Services (SPCS):** Run OCI-compliant containers on Snowflake-managed infrastructure
- **Snowflake Postgres:** Fully managed PostgreSQL instances within Snowflake
- **Stage Volumes:** Mount Snowflake internal stages as filesystem paths inside containers
- **Public Endpoints:** HTTPS endpoints with Snowflake OAuth for browser-accessible services
- **Label Studio:** Open-source data labeling tool by HumanSignal for NLP, CV, and audio tasks

## References

- [Snowpark Container Services documentation](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/overview)
- [Snowflake Postgres documentation](https://docs.snowflake.com/en/user-guide/snowflake-postgres/about)
- [Label Studio documentation](https://labelstud.io/guide/)
- [CREATE POSTGRES INSTANCE](https://docs.snowflake.com/en/sql-reference/sql/create-postgres-instance)
- [SPCS Service Specification](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/specification-reference)
