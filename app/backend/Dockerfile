# The FOREST app API as one container: the same code you run with `npm start`, with production settings.
#
#   docker build -t forest-api app/backend
#   (normally you run it through deploy/docker-compose.yml, which also puts HTTPS in front of it)
#
# The database file and every uploaded video live in /data: mount a folder or volume there, or they vanish with the container.
# ffmpeg comes with `npm ci` (ffmpeg-static), for both x86 (AWS) and ARM (Oracle Ampere): nothing else to install.

FROM node:22-bookworm-slim

WORKDIR /app

# Dependencies first, so a code change does not reinstall them.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY src ./src
COPY scripts ./scripts
COPY assets ./assets

ENV NODE_ENV=production \
    PORT=3000 \
    DB_FILE=/data/forest-app.db \
    UPLOADS_DIR=/data/uploads

RUN mkdir -p /data && chown -R node:node /data /app
USER node
VOLUME /data
EXPOSE 3000

# Docker marks the container unhealthy (and compose can restart it) when the API stops answering.
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/api/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

CMD ["node", "src/server.js"]
