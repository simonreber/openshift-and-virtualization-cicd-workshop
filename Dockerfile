# ── Stage 1: Build Hugo site ──────────────────────────────────────────────
FROM quay.io/sreber84/hugo:latest AS builder

WORKDIR /build

# Copy Hugo source
COPY page/ .

# Build the static site
RUN hugo --minify

# ── Stage 2: Serve with httpd (Hummingbird) ────────────────────────────────
FROM quay.io/hummingbird/httpd:latest

# Copy built Hugo output into the httpd web root
# Hummingbird httpd serves from /var/www/html by default on port 8080
COPY --from=builder /build/public/ /var/www/html/

# Expose port 8080 (non-root compatible)
EXPOSE 8080
