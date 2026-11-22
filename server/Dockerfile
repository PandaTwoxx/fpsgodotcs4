FROM oven/bun:1.3-alpine AS base
WORKDIR /app

# Install dependencies (none currently, but future-proof)
COPY package.json ./
RUN bun install --frozen-lockfile --production 2>/dev/null || bun install --production

# Copy source
COPY tsconfig.json ./
COPY src/ ./src/

# Non-root user for security
USER bun

EXPOSE 8910

CMD ["bun", "run", "src/index.ts"]
