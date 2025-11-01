#!/usr/bin/env bash
# Debug DAPS client authentication issues

echo "=========================================="
echo "DAPS Client Debug"
echo "=========================================="
echo ""

# Check DAPS logs
echo "Checking DAPS logs for authentication errors..."
echo ""
docker compose logs omejdn-server 2>/dev/null | tail -50

echo ""
echo ""

# Check current clients configuration
echo "=========================================="
echo "Current Clients Configuration"
echo "=========================================="
echo ""

if [ -f "config/clients.yml" ]; then
    echo "Contents of config/clients.yml:"
    cat config/clients.yml
else
    echo "config/clients.yml not found"
fi

echo ""
echo ""

# Check if DAPS can read the config
echo "=========================================="
echo "DAPS Config Inside Container"
echo "=========================================="
echo ""

echo "Checking if DAPS can see the clients config..."
docker compose exec omejdn-server cat /opt/config/clients.yml 2>/dev/null || echo "Cannot read config from container"

echo ""
echo ""

# Check DAPS configuration
echo "=========================================="
echo "DAPS Server Configuration"
echo "=========================================="
echo ""

docker compose exec omejdn-server cat /opt/config/omejdn.yml 2>/dev/null || echo "Cannot read omejdn.yml"

echo ""
echo ""

# Check what authentication methods DAPS supports
echo "=========================================="
echo "Testing DAPS Endpoints"
echo "=========================================="
echo ""

echo "DAPS JWKS (public keys):"
curl -k -s https://localhost/auth/jwks.json | jq '.' 2>/dev/null || curl -k -s https://localhost/auth/jwks.json

echo ""
echo ""

echo "DAPS OpenID Configuration:"
curl -k -s https://localhost/auth/.well-known/openid-configuration | jq '.token_endpoint_auth_methods_supported' 2>/dev/null || echo "Could not get auth methods"

echo ""
echo ""

# Try different authentication methods
echo "=========================================="
echo "Testing Different Auth Methods"
echo "=========================================="
echo ""

# Method 1: client_secret_basic (default)
echo "Method 1: client_secret_basic"
curl -k -s -X POST https://localhost/auth/token \
  -u "test-client:test-secret-123" \
  -d "grant_type=client_credentials" \
  -d "scope=idsc:IDS_CONNECTOR_ATTRIBUTES_ALL" | jq '.' 2>/dev/null || \
curl -k -s -X POST https://localhost/auth/token \
  -u "test-client:test-secret-123" \
  -d "grant_type=client_credentials" \
  -d "scope=idsc:IDS_CONNECTOR_ATTRIBUTES_ALL"

echo ""
echo ""

# Method 2: client_secret_post
echo "Method 2: client_secret_post"
curl -k -s -X POST https://localhost/auth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=test-client" \
  -d "client_secret=test-secret-123" \
  -d "scope=idsc:IDS_CONNECTOR_ATTRIBUTES_ALL" | jq '.' 2>/dev/null || \
curl -k -s -X POST https://localhost/auth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=test-client" \
  -d "client_secret=test-secret-123" \
  -d "scope=idsc:IDS_CONNECTOR_ATTRIBUTES_ALL"

echo ""
echo ""

# Check if there are example clients already configured
echo "=========================================="
echo "Existing Clients Analysis"
echo "=========================================="
echo ""

if [ -f "config/clients.yml" ]; then
    echo "Number of clients configured:"
    grep -c "^- client_id:" config/clients.yml || echo "0"

    echo ""
    echo "Client IDs found:"
    grep "client_id:" config/clients.yml

    echo ""
    echo "First client example (for format reference):"
    head -30 config/clients.yml
fi

echo ""
