# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=bioconductor/bioconductor_docker@sha256:359702d482e70e343d2a436731b7c6deffd1ec184a1f1700de5d64b0c97cacba
FROM ${BASE_IMAGE}

ARG TARGETARCH
ARG BASE_IMAGE_INDEX_DIGEST=sha256:359702d482e70e343d2a436731b7c6deffd1ec184a1f1700de5d64b0c97cacba
ARG BUILD_NCPUS=2

LABEL org.opencontainers.image.title="scworkbench core CPU runtime" \
      org.opencontainers.image.description="scworkbench and PyBench CPU runtime for local Docker use" \
      org.opencontainers.image.source="https://gitlab.liu.se/hende58/scworkbench" \
      org.opencontainers.image.version="0.1.0" \
      scworkbench.runtime="docker" \
      scworkbench.stack="full-cpu"

ENV LC_ALL=C.UTF-8 \
    LANG=C.UTF-8 \
    PYTHONUNBUFFERED=1 \
    RETICULATE_PYTHON=/opt/pyenv/bin/python \
    PYBENCH_MATRIX_READ_CHUNK_CELLS=1 \
    PATH=/opt/pyenv/bin:/usr/local/bin:${PATH} \
    SCWORKBENCH_RUNTIME_KIND=docker \
    SCWORKBENCH_RUNTIME_ARCH=${TARGETARCH} \
    SCWORKBENCH_BASE_IMAGE_DIGEST=${BASE_IMAGE_INDEX_DIGEST} \
    SCWORKBENCH_BUILD_NCPUS=${BUILD_NCPUS}

COPY scworkbench /opt/scworkbench
COPY pybench /opt/pybench
COPY install_fullstack.sh /tmp/install_fullstack.sh
COPY scworkbench/containers/docker/Makevars /opt/scworkbench-runtime/Makevars

RUN chmod +x /tmp/install_fullstack.sh \
    && export R_MAKEVARS_USER=/opt/scworkbench-runtime/Makevars \
    && /tmp/install_fullstack.sh \
    && rm -f /tmp/install_fullstack.sh

WORKDIR /work
ENTRYPOINT ["/bin/bash"]
