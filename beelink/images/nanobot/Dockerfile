ARG NANOBOT_BASE=nanobot-upstream:local
FROM ${NANOBOT_BASE}

USER root

# Add local CLI and stdio MCP dependencies here, keeping upstream untouched.
RUN apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

USER nanobot
