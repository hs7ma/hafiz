FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html privacy.html terms.html styles.css animations.js robots.txt logo.svg logo-on-dark.svg og-image.png favicon-32.png apple-touch-icon.png hafiz.apk /usr/share/nginx/html/
COPY illustrations/*.svg /usr/share/nginx/html/illustrations/

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
