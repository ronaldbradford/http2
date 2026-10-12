# HTTP/2 downgrade demo. Pins: Python 3.13.16, Node 20.20.2, and
# requirements.txt (mitmproxy, Playwright, matplotlib).
# Certs and private keys are generated at container start, not baked into the image.
FROM python:3.13.16-slim-bookworm

ARG NODE_VERSION=20.20.2
ARG NODE_SHA256_AMD64=df770b2a6f130ed8627c9782c988fda9669fa23898329a61a871e32f965e007d
ARG NODE_SHA256_ARM64=73093db209e4e9e09dd7d15a47aeaab1b74833830df03efa5f942a1122c5fa71

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    MPLCONFIGDIR=/tmp/matplotlib \
    LISTEN_HOST=0.0.0.0

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash ca-certificates curl openssl procps xz-utils \
    && arch="$(dpkg --print-architecture)" \
    && case "$arch" in \
         amd64) node_arch=x64; node_sha="$NODE_SHA256_AMD64" ;; \
         arm64) node_arch=arm64; node_sha="$NODE_SHA256_ARM64" ;; \
         *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
       esac \
    && curl -fsSL -o /tmp/node.tar.xz "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" \
    && echo "${node_sha}  /tmp/node.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
    && rm /tmp/node.tar.xz \
    && rm -rf /var/lib/apt/lists/* \
    && node --version

WORKDIR /app

COPY requirements.txt .
RUN python3 -m venv /app/.venv \
    && /app/.venv/bin/pip install --no-cache-dir -r requirements.txt \
    && /app/.venv/bin/playwright install --with-deps chromium \
    && chrome="$(find /ms-playwright -type f -name chrome -path '*chrome-linux*' | head -n 1)" \
    && test -n "$chrome" \
    && ln -sfn "$chrome" /usr/local/bin/google-chrome \
    && google-chrome --version

COPY . .
RUN chmod +x run-all.sh docker-entrypoint.sh scripts/*.sh \
    && mkdir -p /app/results /app/logs /app/certs

EXPOSE 8443 8080 8081

ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["benchmark"]
