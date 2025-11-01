#!/usr/bin/env bash
# Find the correct API documentation endpoint

CONNECTOR_URL="${1:-https://localhost/connector}"

echo "Searching for API documentation endpoints..."
echo ""

# Common Swagger/OpenAPI endpoints
ENDPOINTS=(
  "/api/docs"
  "/v3/api-docs"
  "/swagger-ui.html"
  "/swagger-ui/index.html"
  "/swagger-ui/"
  "/api-docs"
  "/openapi.json"
  "/openapi.yaml"
  "/v3/api-docs/swagger-config"
)

for endpoint in "${ENDPOINTS[@]}"; do
  HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "$CONNECTOR_URL$endpoint")
  if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ Found: $CONNECTOR_URL$endpoint (HTTP $HTTP_CODE)"
  fi
done

echo ""
echo "Try these URLs in your browser:"
echo "  - https://localhost:8081/swagger-ui/index.html"
echo "  - https://localhost:8081/v3/api-docs"
echo "  - http://localhost:8081/swagger-ui/index.html"
echo ""
