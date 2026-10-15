FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip python3-dev && \
    rm -rf /var/lib/apt/lists/*

# Install RAPIDS cuGraph from the RAPIDS pip index (CUDA 12 wheels)
RUN pip3 install --no-cache-dir --extra-index-url https://pypi.nvidia.com \
    cudf-cu12 cugraph-cu12 pylibcugraph-cu12 pylibraft-cu12 rmm-cu12 \
    snowflake-snowpark-python[pandas]

WORKDIR /app
COPY leiden_job.py .

ENTRYPOINT ["python3", "leiden_job.py"]
