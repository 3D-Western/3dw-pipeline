FROM ghcr.io/windmill-labs/windmill:latest

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        blender \
        openscad \
        xvfb \
    && rm -rf /var/lib/apt/lists/*

USER windmill
