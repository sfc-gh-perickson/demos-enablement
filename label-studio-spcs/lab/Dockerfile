FROM heartexlabs/label-studio:latest

# Set data directory for persistent storage
ENV DATA_DIR=/label-studio/data
ENV LABEL_STUDIO_LOCAL_FILES_SERVING_ENABLED=true
ENV LABEL_STUDIO_LOCAL_FILES_DOCUMENT_ROOT=/label-studio/files

# Health check for SPCS readiness probe
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

EXPOSE 8080
