FROM node:22-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    jq \
    openssh-client \
  && rm -rf /var/lib/apt/lists/*

RUN npm install --global opencode-ai

WORKDIR /opt/gitea-opencode
COPY package.json ./
COPY bin ./bin
COPY src ./src
COPY docker-entrypoint.sh ./docker-entrypoint.sh

RUN chmod +x /opt/gitea-opencode/bin/gitea-opencode.mjs \
  && chmod +x /opt/gitea-opencode/docker-entrypoint.sh \
  && ln -s /opt/gitea-opencode/bin/gitea-opencode.mjs /usr/local/bin/gitea-opencode

ENTRYPOINT ["/opt/gitea-opencode/docker-entrypoint.sh"]
