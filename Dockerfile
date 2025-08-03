ARG UPSTREAM_VERSION=v0.15.0
FROM nethermind/juno:${UPSTREAM_VERSION}

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -r juno && useradd -r -g juno -d /var/lib/juno -s /bin/bash juno \
    && mkdir -p /var/lib/juno/keys \
    && chown -R juno:juno /var/lib/juno

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 6060 6061 9090

USER juno
WORKDIR /var/lib/juno

ENTRYPOINT ["/entrypoint.sh"]
