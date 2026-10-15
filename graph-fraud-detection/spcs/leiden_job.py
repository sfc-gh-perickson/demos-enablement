"""
cuGraph Leiden community detection job for SPCS.

Reads the applicant edge table, runs GPU-accelerated Leiden clustering,
computes degree centrality, and writes results back to Snowflake.
Designed to run as an SPCS Job Service — starts, processes, exits.
"""

import os
import sys
import time

import cudf
import cugraph
from snowflake.snowpark import Session


def create_session() -> Session:
    return Session.builder.configs({
        "account": os.environ["SNOWFLAKE_ACCOUNT"],
        "host": os.environ["SNOWFLAKE_HOST"],
        "authenticator": "oauth",
        "token": open("/snowflake/session/token").read(),
        "database": os.environ.get("SNOWFLAKE_DATABASE", "GRAPH_FRAUD_DEMO"),
        "schema": "EDGES",
        "warehouse": os.environ.get("SNOWFLAKE_WAREHOUSE", "GRAPH_FRAUD_WH"),
    }).create()


def run_leiden(session: Session, resolution: float = 1.0) -> None:
    timings = {}

    # Phase 1: Read edges from Snowflake
    t0 = time.time()
    print("Reading edge table...")
    edges_pdf = session.table("APPLICANT_EDGES").select(
        "APPLICANT_A", "APPLICANT_B", "WEIGHT"
    ).to_pandas()
    timings["1_data_load"] = time.time() - t0

    if edges_pdf.empty:
        print("No edges found — skipping Leiden.")
        return

    # Phase 2: Convert to cuDF and build graph
    t0 = time.time()
    print(f"Loaded {len(edges_pdf):,} edges. Building cuGraph graph...")
    edges_gdf = cudf.from_pandas(edges_pdf)
    edges_gdf.columns = ["src", "dst", "weight"]
    edges_gdf["src"] = edges_gdf["src"].astype("int32")
    edges_gdf["dst"] = edges_gdf["dst"].astype("int32")
    edges_gdf["weight"] = edges_gdf["weight"].astype("float32")

    G = cugraph.Graph()
    G.from_cudf_edgelist(edges_gdf, source="src", destination="dst", edge_attr="weight")
    timings["2_graph_build"] = time.time() - t0
    print(f"Graph has {G.number_of_vertices():,} vertices, {G.number_of_edges():,} edges.")

    # Phase 3: Run Leiden
    t0 = time.time()
    print(f"Running Leiden (resolution={resolution})...")
    parts, modularity = cugraph.leiden(G, resolution=resolution)
    timings["3_leiden"] = time.time() - t0
    print(f"Leiden complete. Modularity: {modularity:.4f}, communities: {parts['partition'].nunique()}")

    # Phase 4: Degree centrality
    t0 = time.time()
    print("Computing degree centrality...")
    centrality = cugraph.degree_centrality(G)
    timings["4_centrality"] = time.time() - t0

    # Phase 5: Assemble results
    t0 = time.time()
    results = parts.merge(centrality, on="vertex", how="left")
    results.columns = ["APPLICANT_ID", "COMMUNITY_ID", "DEGREE_CENTRALITY"]
    community_sizes = results.groupby("COMMUNITY_ID").size().reset_index()
    community_sizes.columns = ["COMMUNITY_ID", "COMMUNITY_SIZE"]
    results = results.merge(community_sizes, on="COMMUNITY_ID", how="left")
    results_pdf = results.to_pandas()
    results_pdf["MODULARITY"] = modularity
    timings["5_postprocess"] = time.time() - t0

    # Phase 6: Write back to Snowflake
    t0 = time.time()
    print(f"Writing {len(results_pdf):,} rows to GRAPH.COMMUNITY_RESULTS...")
    session.use_schema("GRAPH")
    session.write_pandas(
        results_pdf,
        table_name="COMMUNITY_RESULTS",
        overwrite=True,
        auto_create_table=True,
    )

    session.sql("""
        MERGE INTO GRAPH.COMMUNITY_ASSIGNMENTS tgt
        USING GRAPH.COMMUNITY_RESULTS src
            ON tgt.APPLICANT_ID = src.APPLICANT_ID
        WHEN MATCHED THEN UPDATE SET
            tgt.COMMUNITY_ID = src.COMMUNITY_ID,
            tgt.ASSIGNMENT_SOURCE = 'LEIDEN',
            tgt.CONFIDENCE = 1.0,
            tgt.ASSIGNED_AT = CURRENT_TIMESTAMP()
        WHEN NOT MATCHED THEN INSERT (
            APPLICANT_ID, COMMUNITY_ID, ASSIGNMENT_SOURCE, CONFIDENCE, ASSIGNED_AT
        ) VALUES (
            src.APPLICANT_ID, src.COMMUNITY_ID, 'LEIDEN', 1.0, CURRENT_TIMESTAMP()
        )
    """).collect()
    timings["6_write_back"] = time.time() - t0

    # Benchmark summary
    total = sum(timings.values())
    print("\n" + "=" * 60)
    print("BENCHMARK: Leiden Community Detection on GPU")
    print(f"  Edges: {len(edges_pdf):,}  |  Vertices: {G.number_of_vertices():,}")
    print("=" * 60)
    for phase, secs in timings.items():
        pct = secs / total * 100
        print(f"  {phase:<20s}  {secs:7.2f}s  ({pct:5.1f}%)")
    print(f"  {'TOTAL':<20s}  {total:7.2f}s")
    print("=" * 60)
    print("Done.")


def main() -> None:
    resolution = float(os.environ.get("LEIDEN_RESOLUTION", "1.0"))
    session = create_session()
    try:
        run_leiden(session, resolution=resolution)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        raise
    finally:
        session.close()


if __name__ == "__main__":
    main()
