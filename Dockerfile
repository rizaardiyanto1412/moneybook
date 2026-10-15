# Self-hosted Moneybook (API + MCP + web app) for a VPS.
#   docker build -t moneybook . && docker run -d -p 8787:8787 -v moneybook-data:/data -e API_TOKEN=... moneybook
FROM node:26-slim
WORKDIR /app/server
COPY server/package.json server/package-lock.json ./
RUN npm ci --omit=dev && npm install --no-save tsx
COPY server/src ./src
COPY web /app/web
ENV DATA_DIR=/data PORT=8787 NODE_ENV=production
VOLUME /data
EXPOSE 8787
CMD ["npx", "tsx", "src/node.ts"]
