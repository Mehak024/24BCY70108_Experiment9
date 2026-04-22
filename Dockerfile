# ─────────────────────────────────────────
# Stage 1: Build
# ─────────────────────────────────────────
FROM node:18-alpine AS builder

WORKDIR /app

# Copy package files first for better layer caching
COPY package.json package-lock.json ./
RUN npm ci

# Copy source and build
COPY . .
RUN npm run build

# ─────────────────────────────────────────
# Stage 2: Production (Nginx)
# ─────────────────────────────────────────
FROM nginx:stable-alpine AS production

# Copy built assets from builder
COPY --from=builder /app/build /usr/share/nginx/html

# Copy custom Nginx config (optional)
# COPY nginx.conf /etc/nginx/conf.d/default.conf

# React Router support — redirect all routes to index.html
RUN printf 'server {\n  listen 80;\n  root /usr/share/nginx/html;\n  location / {\n    try_files $uri $uri/ /index.html;\n  }\n}' \
    > /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
