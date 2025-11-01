#!/usr/bin/env bash
# Diagnostic script to check container health and connectivity

echo "=== Container Status ==="
docker compose ps

echo ""
echo "=== Checking Connector Service ==="
docker compose logs connector | tail -20

echo ""
echo "=== Checking Nginx Service ==="
docker compose logs nginx | tail -20

echo ""
echo "=== Testing Internal Connectivity ==="
echo "Testing connector HTTP..."
docker compose exec nginx curl -s -o /dev/null -w "HTTP: %{http_code}\n" http://connector:8081/ || echo "HTTP connection failed"

echo "Testing connector HTTPS..."
docker compose exec nginx curl -k -s -o /dev/null -w "HTTPS: %{http_code}\n" https://connector:8081/ || echo "HTTPS connection failed"

echo ""
echo "=== Testing from Host ==="
echo "Testing direct port access..."
curl -s -o /dev/null -w "Direct HTTP (8081): %{http_code}\n" http://localhost:8081/ || echo "Direct connection failed"

echo "Testing nginx proxy..."
curl -k -s -o /dev/null -w "Nginx HTTPS: %{http_code}\n" https://localhost/connector/ || echo "Nginx proxy failed"

echo ""
echo "=== Checking Nginx Configuration ==="
docker compose exec nginx nginx -t
