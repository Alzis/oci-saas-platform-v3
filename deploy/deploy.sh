
#!/bin/bash

cd /opt/platform

docker compose pull

docker compose up -d --build
