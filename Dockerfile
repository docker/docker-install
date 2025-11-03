FROM nginx:alpine
COPY site/ /usr/share/nginx/html
EXPOSE 80
