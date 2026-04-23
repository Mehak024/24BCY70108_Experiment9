##############################################################
# Dockerfile — Production-ready multi-stage build
#
# Stage 1 (builder): install deps + compile/bundle
# Stage 2 (runner):  minimal image with only runtime artefacts
#
# Adjust the base images and build commands for your stack.
# Example shown: Node.js application.
##############################################################

# ── Stage 1: Build ───────────────────────────────────────────
FROM node:20-alpine AS builder

# Security: run as non-root during build
WORKDIR /app

# Copy dependency manifests first (layer cache optimisation)
COPY package.json package-lock.json ./

# Install all deps (including devDependencies needed for build)
RUN npm ci --frozen-lockfile

# Copy source
COPY . .

# Build the application (adjust for your framework)
RUN npm run build

# Prune dev dependencies
RUN npm prune --production

# ── Stage 2: Runtime ─────────────────────────────────────────
FROM node:20-alpine AS runner

# Security labels
LABEL maintainer="your-team@example.com"
LABEL org.opencontainers.image.source="https://github.com/your-org/your-repo"

# Install only essential runtime OS packages
RUN apk add --no-cache \
    curl \
    dumb-init \
    && rm -rf /var/cache/apk/*

WORKDIR /app

# Copy pruned node_modules and build output from builder
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist        ./dist
COPY --from=builder /app/package.json ./

# Security: create and use a non-root user
RUN addgroup --system --gid 1001 nodejs \
    && adduser  --system --uid 1001 appuser \
    && chown -R appuser:nodejs /app

USER appuser

# Expose application port
EXPOSE 3000

# Health check (ALB also performs its own; this lets Docker/ECS
# detect unhealthy containers before the ALB does)
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Use dumb-init to handle PID 1 signals and reap zombies
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "dist/server.js"]
