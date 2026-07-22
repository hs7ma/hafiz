FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html styles.css logo.svg /usr/share/nginx/html/

# Optional: add hafiz.apk beside these files before deploy, or upload later
# COPY hafiz.apk /usr/share/nginx/html/

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
