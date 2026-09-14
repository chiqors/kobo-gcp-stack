FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release util-linux \
    && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
       | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt gcsfuse-$(lsb_release -c -s) main" \
       > /etc/apt/sources.list.d/gcsfuse.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gcsfuse \
    && rm -rf /var/lib/apt/lists/*
