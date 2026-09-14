user nginx;
worker_processes auto;
events { worker_connections 2048; }
http {
  include /etc/nginx/mime.types;
  default_type application/octet-stream;
  sendfile on;
  client_max_body_size 100M;
  server_tokens off;
  resolver 127.0.0.11 ipv6=off valid=10s;
  map $http_upgrade $connection_upgrade { default upgrade; '' close; }
  server {
    listen 80 default_server;
    listen __INTERNAL_API_PORT__ default_server;
    server_name _;
    return 444;
  }
  server {
    listen 80;
    listen __INTERNAL_API_PORT__;
    server_name __KPI__ __KPI_INTERNAL__;
    location /static/ { alias /srv/www/; }
    location /media/__public/ { alias /srv/kpi_media/__public/; }
    location /protected/ { internal; alias /media/; }
    location / { set $kpi_upstream kpi:8000; include /etc/nginx/uwsgi_params; uwsgi_pass $kpi_upstream; uwsgi_param HTTP_HOST $http_host; uwsgi_param HTTP_X_FORWARDED_PROTO $http_x_forwarded_proto; uwsgi_param HTTP_X_FORWARDED_FOR $proxy_add_x_forwarded_for; }
  }
  server {
    listen 80;
    listen __INTERNAL_API_PORT__;
    server_name __KC__ __KC_INTERNAL__;
    location /static/ { alias /srv/www/; }
    location /protected/ { internal; alias /media/; }
    location / { set $kpi_upstream kpi:8000; include /etc/nginx/uwsgi_params; uwsgi_pass $kpi_upstream; uwsgi_param HTTP_HOST $http_host; uwsgi_param HTTP_X_FORWARDED_PROTO $http_x_forwarded_proto; uwsgi_param HTTP_X_FORWARDED_FOR $proxy_add_x_forwarded_for; }
  }
  server {
    listen 80;
    listen __INTERNAL_API_PORT__;
    server_name __EE__ __EE_INTERNAL__;
    location / { set $enketo_upstream enketo:8005; proxy_pass http://$enketo_upstream; proxy_set_header Host $http_host; proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection $connection_upgrade; }
  }
}
