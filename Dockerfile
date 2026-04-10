FROM quay.io/hummingbird/httpd:latest

# Copy built Hugo output into the httpd web root
# Hummingbird httpd serves from /var/www/html by default on port 8080
COPY /public/ /var/www/html/

# Expose port 8080 (non-root compatible)
EXPOSE 8080
