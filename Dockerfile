ARG RUNNER_BASE=summerwind/actions-runner
ARG RUNNER_TAG=ubuntu-24.04
FROM ${RUNNER_BASE}:${RUNNER_TAG}

USER root

ARG BUILDX_VERSION=0.35.0
ARG DOCKER_VERSION=29.1.3
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

USER runner

# Fail the build if the plugin is not visible to the runner user
RUN docker --version && docker buildx version
