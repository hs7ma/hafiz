FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html styles.css animations.js robots.txt logo.svg logo-on-dark.svg hafiz.apk /usr/share/nginx/html/
COPY illustrations/link.svg illustrations/mushaf.svg illustrations/attendance.svg /usr/share/nginx/html/illustrations/

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
