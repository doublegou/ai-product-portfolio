FROM nginx:1.27-alpine

COPY deploy/web/default.conf /etc/nginx/conf.d/default.conf
COPY index.html styles.css script.js /usr/share/nginx/html/
COPY assets /usr/share/nginx/html/assets
COPY products /usr/share/nginx/html/products

