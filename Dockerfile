# ─────────────────────────────────────────────────────────────
# Stage 1 — deps
# Install production + dev dependencies, cached as a separate
# layer so rebuilds skip this when package.json hasn't changed
# ─────────────────────────────────────────────────────────────
FROM node:18-alpine AS deps

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

# ─────────────────────────────────────────────────────────────
# Stage 2 — builder
# Copy source, build the production React bundle
# ─────────────────────────────────────────────────────────────
FROM node:18-alpine AS builder

WORKDIR /app

# Inherit node_modules from deps stage (no reinstall)
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Set NODE_ENV so CRA builds an optimised bundle
ENV NODE_ENV=production

# Uncomment and set any public runtime env vars:
# ENV REACT_APP_API_URL=https://api.example.com

RUN npm run build

# ─────────────────────────────────────────────────────────────
# Stage 3 — production
# Serve the static build with Nginx; ~25 MB final image
# ─────────────────────────────────────────────────────────────
FROM nginx:1.25-alpine AS production

# Remove default Nginx site
RUN rm /etc/nginx/conf.d/default.conf

# React Router support: all unmatched paths → index.html
COPY <<'EOF' /etc/nginx/conf.d/default.conf
server {
    listen       80;
    server_name  _;
    root         /usr/share/nginx/html;
    index        index.html;

    # Serve pre-compressed assets if available
    gzip_static on;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # Cache static assets aggressively; React content-hashes filenames
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff2?)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Don't cache index.html so users always get the latest app shell
    location = /index.html {
        add_header Cache-Control "no-cache";
    }
}
EOF

COPY --from=builder /app/build /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget -q --spider http://localhost/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
