FROM nginx:stable
EXPOSE 80
COPY maintenance.conf /etc/nginx/conf.d/default.conf
COPY maintenance.html /usr/share/nginx/html/index.html
COPY maintenance.html /usr/share/nginx/html/maintenance.html
STOPSIGNAL SIGQUIT
CMD ["nginx", "-g", "daemon off;"]
