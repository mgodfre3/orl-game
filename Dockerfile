# Use an official Node.js image as the base
FROM nginx:alpine
COPY mario-clone/ /usr/share/nginx/html
EXPOSE 80
