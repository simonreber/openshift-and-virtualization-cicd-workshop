# ── Kickstart HTTP Server ─────────────────────────────────────────────────
# Serves the kickstart file (and any auxiliary files) over plain HTTP
# using the Hummingbird httpd image.
#
# IMPORTANT: Plain HTTP is required — Anaconda's kickstart fetcher can
# have trouble with TLS certificate validation in some environments.
# The Route is configured with insecureEdgeTerminationPolicy: Allow so
# the VM installer can reach it on http://.
#
# The kickstart file is embedded at build time via COPY.
# To update the kickstart file, rebuild and push this image.
#
FROM quay.io/hummingbird/httpd:latest

# Copy kickstart file into the httpd web root
# Hummingbird httpd serves from /var/www/html on port 8080
COPY centos10-workshop.ks /var/www/html/centos10-workshop.ks

# Optional: copy additional files (e.g., post-install scripts)
# COPY scripts/ /var/www/html/scripts/

EXPOSE 8080
