#!/usr/bin/env bash
# Fix the DAPS client configuration

echo "=========================================="
echo "Fixing DAPS Client Configuration"
echo "=========================================="
echo ""

# Backup the current config
cp config/clients.yml config/clients.yml.broken.backup
echo "Backup created: config/clients.yml.broken.backup"
echo ""

# Create a clean clients.yml with correct format
cat > config/clients.yml <<'EOF'
---
# DAPS Clients Configuration
# Format compatible with Omejdn 1.6.0

- client_id: test-client
  client_name: Test Client
  grant_types:
    - client_credentials
  token_endpoint_auth_method: client_secret_post
  scope:
    - idsc:IDS_CONNECTOR_ATTRIBUTES_ALL
  attributes:
    - key: idsc
      value: IDS_CONNECTOR_ATTRIBUTES_ALL
    - key: securityProfile
      value: idsc:BASE_SECURITY_PROFILE
  client_secret: test-secret-123

- client_id: admin
  client_name: Admin Client
  grant_types:
    - client_credentials
    - password
  token_endpoint_auth_method: client_secret_post
  scope:
    - idsc:IDS_CONNECTOR_ATTRIBUTES_ALL
    - omejdn:admin
  attributes:
    - key: idsc
      value: IDS_CONNECTOR_ATTRIBUTES_ALL
    - key: securityProfile
      value: idsc:BASE_SECURITY_PROFILE
  client_secret: admin
EOF

echo "Created new clients.yml with:"
echo "  - test-client (for testing)"
echo "  - admin (admin client)"
echo ""

# Show the new config
echo "New configuration:"
cat config/clients.yml
echo ""

# Restart DAPS
echo "Restarting DAPS..."
docker compose restart omejdn-server

echo ""
echo "Waiting for DAPS to start..."
sleep 10

# Test token acquisition
echo ""
echo "=========================================="
echo "Testing Token Acquisition"
echo "=========================================="
echo ""

echo "Attempting to get token for test-client..."
TOKEN_RESPONSE=$(curl -k -s -X POST https://localhost/auth/token \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials" \
    -d "client_id=test-client" \
    -d "client_secret=test-secret-123" \
    -d "scope=idsc:IDS_CONNECTOR_ATTRIBUTES_ALL")

echo "$TOKEN_RESPONSE" | jq '.' 2>/dev/null || echo "$TOKEN_RESPONSE"

# Check if we got a token
if echo "$TOKEN_RESPONSE" | grep -q "access_token"; then
    echo ""
    echo "✓✓✓ SUCCESS! Token obtained"

    # Extract and save token
    TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token' 2>/dev/null)
    echo "$TOKEN" > /tmp/daps-token.txt

    echo ""
    echo "Token saved to: /tmp/daps-token.txt"
    echo ""
    echo "Test with:"
    echo "  curl -k -H \"Authorization: Bearer \$(cat /tmp/daps-token.txt)\" https://localhost:8081/api/offers"
else
    echo ""
    echo "⚠ Token request failed"
    echo ""
    echo "Checking DAPS logs..."
    docker compose logs omejdn-server | tail -30
fi

echo ""
