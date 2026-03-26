FROM node:lts-trixie-slim AS base
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl git \
  && rm -rf /var/lib/apt/lists/*
RUN corepack enable

FROM base AS source
WORKDIR /app
ARG PAPERCLIP_REPOSITORY=https://github.com/paperclipai/paperclip.git
ARG PAPERCLIP_REF=
RUN if [ -n "$PAPERCLIP_REF" ]; then \
    git init . \
    && git remote add origin "$PAPERCLIP_REPOSITORY" \
    && (git fetch --depth=1 origin "$PAPERCLIP_REF" && git checkout FETCH_HEAD || (rm -rf .git && git clone --depth=1 "$PAPERCLIP_REPOSITORY" .)); \
  else \
    git clone --depth=1 "$PAPERCLIP_REPOSITORY" .; \
  fi

FROM base AS deps
WORKDIR /app
COPY --from=source /app/package.json /app/pnpm-workspace.yaml /app/pnpm-lock.yaml /app/.npmrc ./
COPY --from=source /app/cli/package.json cli/
COPY --from=source /app/server/package.json server/
COPY --from=source /app/ui/package.json ui/
COPY --from=source /app/packages/shared/package.json packages/shared/
COPY --from=source /app/packages/db/package.json packages/db/
COPY --from=source /app/packages/adapter-utils/package.json packages/adapter-utils/
COPY --from=source /app/packages/adapters/claude-local/package.json packages/adapters/claude-local/
COPY --from=source /app/packages/adapters/codex-local/package.json packages/adapters/codex-local/
COPY --from=source /app/packages/adapters/cursor-local/package.json packages/adapters/cursor-local/
COPY --from=source /app/packages/adapters/gemini-local/package.json packages/adapters/gemini-local/
COPY --from=source /app/packages/adapters/openclaw-gateway/package.json packages/adapters/openclaw-gateway/
COPY --from=source /app/packages/adapters/opencode-local/package.json packages/adapters/opencode-local/
COPY --from=source /app/packages/adapters/pi-local/package.json packages/adapters/pi-local/
COPY --from=source /app/packages/plugins/sdk/package.json packages/plugins/sdk/
COPY --from=source /app/patches/ patches/
RUN pnpm install --frozen-lockfile

FROM base AS build
WORKDIR /app
COPY --from=deps /app /app
COPY --from=source /app .
RUN pnpm --filter @paperclipai/ui build
RUN pnpm --filter @paperclipai/plugin-sdk build
RUN pnpm --filter @paperclipai/server build
RUN test -f server/dist/index.js || (echo "ERROR: server build output missing" && exit 1)

FROM base AS production
WORKDIR /app
COPY --chown=node:node --from=build /app /app
RUN npm install --global --omit=dev @anthropic-ai/claude-code@latest @openai/codex@latest opencode-ai \
  && mkdir -p /paperclip \
  && chown node:node /paperclip \
  && chsh -s /bin/bash node

ENV NODE_ENV=production \
  HOME=/paperclip \
  HOST=0.0.0.0 \
  PORT=3100 \
  SERVE_UI=true \
  PAPERCLIP_HOME=/paperclip \
  PAPERCLIP_INSTANCE_ID=default \
  PAPERCLIP_CONFIG=/paperclip/instances/default/config.json \
  PAPERCLIP_DEPLOYMENT_MODE=authenticated \
  PAPERCLIP_DEPLOYMENT_EXPOSURE=private

VOLUME ["/paperclip"]
EXPOSE 3100

USER node
CMD ["sh", "-lc", "PUBLIC_URL=\"${PAPERCLIP_PUBLIC_URL:-}\"; if [ -z \"$PUBLIC_URL\" ] && [ -n \"${SERVICE_FQDN_SERVER_3100:-}\" ]; then PUBLIC_URL=\"https://${SERVICE_FQDN_SERVER_3100}\"; fi; if [ -z \"$PUBLIC_URL\" ] && [ -n \"${SERVICE_FQDN_SERVER:-}\" ]; then PUBLIC_URL=\"https://${SERVICE_FQDN_SERVER}\"; fi; if [ ! -f /paperclip/instances/default/config.json ]; then pnpm paperclipai onboard -y || true; fi; if [ -n \"$PUBLIC_URL\" ]; then ALLOWED_HOSTNAME=$(printf '%s' \"$PUBLIC_URL\" | sed -E 's#^[a-zA-Z]+://##; s#/.*$##; s/:.*$##'); if [ -n \"$ALLOWED_HOSTNAME\" ]; then pnpm paperclipai allowed-hostname \"$ALLOWED_HOSTNAME\" || true; fi; fi; node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js & SERVER_PID=$!; if [ \"${PAPERCLIP_AUTO_BOOTSTRAP_CEO:-true}\" = \"true\" ] && [ ! -f /paperclip/bootstrap-ceo-url.txt ]; then for i in $(seq 1 60); do if curl -fsS \"http://127.0.0.1:${PORT:-3100}/\" >/dev/null 2>&1; then break; fi; sleep 2; done; BOOTSTRAP_OUTPUT=$(pnpm paperclipai auth bootstrap-ceo 2>&1 || true); printf '%s\n' \"$BOOTSTRAP_OUTPUT\" | tee /paperclip/bootstrap-ceo-url.txt; fi; wait $SERVER_PID"]
