#!/bin/sh
# escribe la url de la api que recibe el contenedor en js/config.js
echo "window.API_URL = '${API_URL:-http://localhost:8000}';" > /usr/share/nginx/html/js/config.js
