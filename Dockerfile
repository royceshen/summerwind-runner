ARG RUNNER_BASE=summerwind/actions-runner
ARG RUNNER_TAG=ubuntu-24.04
FROM ${RUNNER_BASE}:${RUNNER_TAG}

USER root

ARG BUILDX_VERSION=0.35.0
ARG DOCKER_VERSION=29.1.3
ARG AWSCLI_VERSION=2.36.21
ARG YQ_VERSION=4.53.3
ARG TARGETARCH

# buildx as a CLI plugin, installed system-wide so the runner user picks it up
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      amd64) buildx_arch=linux-amd64 ;; \
      arm64) buildx_arch=linux-arm64 ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    mkdir -p /usr/local/lib/docker/cli-plugins; \
    curl -fsSL "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.${buildx_arch}" \
      -o /usr/local/lib/docker/cli-plugins/docker-buildx; \
    chmod 0755 /usr/local/lib/docker/cli-plugins/docker-buildx

# Bump the docker CLI to match the dind server version. The base image may ship
# the CLI at /usr/bin/docker or /usr/local/bin/docker (and it may be a shim), so
# replace whatever is first on PATH instead of hardcoding a path.
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      amd64) docker_arch=x86_64 ;; \
      arm64) docker_arch=aarch64 ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    target="$(command -v docker || echo /usr/bin/docker)"; \
    echo "replacing docker CLI at ${target}"; \
    curl -fsSL "https://download.docker.com/linux/static/stable/${docker_arch}/docker-${DOCKER_VERSION}.tgz" -o /tmp/docker.tgz; \
    tar -xzf /tmp/docker.tgz -C /tmp docker/docker; \
    install -o root -g root -m 0755 /tmp/docker/docker "${target}"; \
    rm -rf /tmp/docker.tgz /tmp/docker

# AWS CLI v2. Installed to /usr/local so it is on the default PATH for the
# runner user and for job steps (the base image ships no aws binary).
# Set AWSCLI_VERSION to "latest" (or empty) to track the moving installer.
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      amd64) awscli_arch=x86_64 ;; \
      arm64) awscli_arch=aarch64 ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    case "${AWSCLI_VERSION:-}" in \
      ""|latest) ver_suffix="" ;; \
      *) ver_suffix="-${AWSCLI_VERSION}" ;; \
    esac; \
    if ! command -v unzip >/dev/null; then \
      apt-get update; \
      apt-get install -y --no-install-recommends unzip; \
      rm -rf /var/lib/apt/lists/*; \
    fi; \
    url="https://awscli.amazonaws.com/awscli-exe-linux-${awscli_arch}${ver_suffix}.zip"; \
    echo "installing aws cli from ${url}"; \
    curl -fsSL "$url" -o /tmp/awscliv2.zip; \
    unzip -q /tmp/awscliv2.zip -d /tmp; \
    /tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update; \
    rm -rf /tmp/awscliv2.zip /tmp/aws

# yq (mikefarah/yq v4) — the CD jobs patch gitops values with `yq e "... = ..." -i`,
# which is v4 syntax. Do NOT swap this for the apt `yq` (a python jq wrapper) or
# for v3: both take different expression syntax and would break those steps.
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      amd64) yq_arch=amd64 ;; \
      arm64) yq_arch=arm64 ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${yq_arch}" \
      -o /usr/local/bin/yq; \
    chmod 0755 /usr/local/bin/yq

# jq is relied on by ad-hoc CI steps; guarantee it rather than trusting the base.
RUN set -eux; \
    if ! command -v jq >/dev/null; then \
      apt-get update; \
      apt-get install -y --no-install-recommends jq; \
      rm -rf /var/lib/apt/lists/*; \
    fi

USER runner

# Fail the build if any tool the CI/CD jobs call is not on the runner user's PATH.
# node is deliberately absent: job steps get it from actions/setup-node, and the
# runner's own node lives in /runner/externals, off the default PATH.
RUN docker --version \
 && docker buildx version \
 && aws --version \
 && yq --version \
 && jq --version \
 && git --version
