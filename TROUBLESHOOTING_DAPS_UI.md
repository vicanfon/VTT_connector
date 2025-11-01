# Troubleshooting DAPS UI Issues

This guide helps you troubleshoot and work around issues with the DAPS (Omejdn) web UI.

## Issue: Login Button Not Working

### Symptoms
- DAPS UI loads at `https://localhost/`
- Login form is visible
- Login button doesn't respond when clicked
- No error messages shown

### Quick Fix: Register Client Without UI

You don't need the UI to register a client! Use the command-line method instead:

```bash
# Register a test client
./scripts/register-daps-client.sh test-client "My Test Client" test-secret-123

# Or use your connector's certificate SKI as client ID
./scripts/register-daps-client.sh
```

This script will:
1. Add the client to `config/clients.yml`
2. Restart DAPS to load the new configuration
3. Test token acquisition
4. Save the token for you to use

## Debugging the UI Issue

### Step 1: Check Browser Console

1. Open browser developer tools (F12)
2. Go to the Console tab
3. Try clicking the login button
4. Look for JavaScript errors

**Common errors:**
- `Mixed Content` - HTTP/HTTPS mixing issue
- `CORS` - Cross-origin request blocked
- `Failed to fetch` - Cannot reach backend
- `Syntax Error` - JavaScript parsing issue

### Step 2: Check Network Tab

1. Open browser developer tools (F12)
2. Go to the Network tab
3. Try clicking the login button
4. Look for failed requests (red entries)

**What to look for:**
- POST requests to `/auth/token` or `/auth/api/v1/...`
- Response codes (401, 403, 500, etc.)
- Request payload (are credentials being sent?)

### Step 3: Check Omejdn UI Logs

```bash
# View UI container logs
docker compose logs omejdn-ui

# Look for errors
docker compose logs omejdn-ui | grep -i error

# Follow logs in real-time
docker compose logs -f omejdn-ui
```

**Common log issues:**
- `OIDC_ISSUER not set` - Environment variable missing
- `Cannot connect to API` - Backend unreachable
- `Invalid configuration` - Config file issue

### Step 4: Check Omejdn Server Logs

```bash
# View DAPS server logs
docker compose logs daps

# Look for authentication attempts
docker compose logs daps | grep -i "auth\|login\|token"

# Check for errors
docker compose logs daps | grep -i error
```

### Step 5: Verify Environment Variables

```bash
# Check Omejdn UI environment
docker compose exec omejdn-ui env

# Should show:
# OIDC_ISSUER=https://localhost/auth/
# API_URL=https://localhost/auth/api/v1
# CLIENT_ID=adminUI

# Check if variables are correct
docker compose exec omejdn-ui cat /etc/nginx/conf.d/default.conf 2>/dev/null || echo "Config not accessible"
```

## Common Causes & Solutions

### Cause 1: HTTPS Certificate Issues

**Symptom:** Mixed content warnings in console

**Solution:**
1. Make sure you've accepted the self-signed certificate warning
2. Visit `https://localhost/auth/` directly and accept the certificate
3. Visit `https://localhost/` again

### Cause 2: CORS Issues

**Symptom:** "CORS policy" errors in console

**Solution:**
Check nginx configuration includes CORS headers:

```bash
# Check nginx config
docker compose exec nginx cat /etc/nginx/nginx.conf | grep -A3 "Access-Control"
```

### Cause 3: Backend Not Reachable

**Symptom:** "Failed to fetch" or "Network error"

**Solution:**
```bash
# Test if DAPS backend is accessible
curl -k https://localhost/auth/.well-known/openid-configuration

# Test if API endpoint works
curl -k https://localhost/auth/api/v1/config
```

If these fail, DAPS server is not running or not accessible.

### Cause 4: Wrong Environment Variables

**Symptom:** UI loads but can't connect to backend

**Solution:**
Check `docker-compose.yml` has correct environment for `omejdn-ui`:

```yaml
omejdn-ui:
  environment:
    - OIDC_ISSUER=https://localhost/auth/
    - API_URL=https://localhost/auth/api/v1
    - CLIENT_ID=adminUI
```

Should match your actual hostname (localhost in local dev).

### Cause 5: JavaScript Not Loading

**Symptom:** Blank page or UI doesn't work at all

**Solution:**
```bash
# Check if UI container is running
docker compose ps omejdn-ui

# Restart the UI
docker compose restart omejdn-ui

# Check UI logs for errors
docker compose logs omejdn-ui
```

## Alternative: Direct File Configuration

You can manage DAPS entirely through configuration files without the UI:

### 1. Register Clients via config/clients.yml

```bash
# Edit the file directly
nano config/clients.yml

# Or use the registration script
./scripts/register-daps-client.sh my-client "My Client" my-secret
```

Example `clients.yml` entry:

```yaml
- client_id: test-client
  client_name: Test Client
  grant_types:
    - client_credentials
  token_endpoint_auth_method: client_secret_basic
  scope:
    - idsc:IDS_CONNECTOR_ATTRIBUTES_ALL
  attributes:
    - key: idsc
      value: IDS_CONNECTOR_ATTRIBUTES_ALL
    - key: securityProfile
      value: idsc:BASE_SECURITY_PROFILE
  metadata:
    client_secret: test-secret-123
```

### 2. Restart DAPS

```bash
docker compose restart daps
```

### 3. Test Token Acquisition

```bash
curl -k -X POST https://localhost/auth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=test-client" \
  -d "client_secret=test-secret-123" \
  -d "scope=idsc:IDS_CONNECTOR_ATTRIBUTES_ALL"
```

## Alternative: Use DAPS API

If the UI doesn't work, you can use the DAPS REST API directly:

### Get Admin Token First

```bash
# Login as admin via API
curl -k -X POST https://localhost/auth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "username=admin" \
  -d "password=admin" \
  -d "client_id=adminUI"
```

### Use Token to Manage Clients

```bash
# Set the admin token
ADMIN_TOKEN="<token from above>"

# List clients
curl -k -H "Authorization: Bearer $ADMIN_TOKEN" \
  https://localhost/auth/api/v1/clients

# Create client
curl -k -X POST \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  https://localhost/auth/api/v1/clients \
  -d '{
    "client_id": "new-client",
    "client_name": "New Client",
    "grant_types": ["client_credentials"],
    "scope": ["idsc:IDS_CONNECTOR_ATTRIBUTES_ALL"]
  }'
```

## Testing Without the UI

You don't actually need the DAPS UI at all for testing! Here's what you can do:

### 1. Register Client via Script

```bash
./scripts/register-daps-client.sh test-client "Test Client" test-secret-123
```

### 2. Get Token

```bash
curl -k -X POST https://localhost/auth/token \
  -d "grant_type=client_credentials" \
  -d "client_id=test-client" \
  -d "client_secret=test-secret-123" \
  -d "scope=idsc:IDS_CONNECTOR_ATTRIBUTES_ALL"
```

### 3. Test Connector

```bash
# Save token
TOKEN="<access_token from above>"

# Test connector endpoint
curl -k -H "Authorization: Bearer $TOKEN" \
  https://localhost:8081/api/offers
```

## Resetting the UI

If the UI is completely broken, try resetting it:

```bash
# Stop and remove UI container
docker compose stop omejdn-ui
docker compose rm -f omejdn-ui

# Recreate it
docker compose up -d omejdn-ui

# Check logs
docker compose logs -f omejdn-ui
```

## Using a Different Browser

Sometimes the issue is browser-specific:

1. Try a different browser (Chrome, Firefox, Edge)
2. Try incognito/private mode
3. Clear browser cache and cookies
4. Disable browser extensions

## Checking DAPS Configuration

Verify the DAPS server configuration:

```bash
# View DAPS config
docker compose exec daps cat /opt/config/omejdn.yml

# Should show issuer, front_url, etc.
```

Expected configuration:

```yaml
issuer: https://localhost/auth
front_url: https://localhost/auth
openid: true
environment: production
accept_audience: idsc:IDS_CONNECTORS_ALL
default_audience: idsc:IDS_CONNECTORS_ALL
```

## When to Skip the UI

You can completely skip the UI if:
- ✅ You're comfortable editing YAML files
- ✅ You can restart Docker containers
- ✅ You only need basic client registration

The UI is optional - all DAPS functionality is available via:
1. Configuration files (`config/clients.yml`)
2. REST API (if enabled)
3. Command-line scripts

## Summary

**The UI issue doesn't block you!** You can:

1. **Register clients without UI:**
   ```bash
   ./scripts/register-daps-client.sh test-client "Test Client" secret-123
   ```

2. **Get tokens directly:**
   ```bash
   curl -k -X POST https://localhost/auth/token \
     -d "grant_type=client_credentials" \
     -d "client_id=test-client" \
     -d "client_secret=secret-123" \
     -d "scope=idsc:IDS_CONNECTOR_ATTRIBUTES_ALL"
   ```

3. **Test connector:**
   ```bash
   curl -k -H "Authorization: Bearer $TOKEN" \
     https://localhost:8081/api/offers
   ```

The UI is just a convenience - you have full control via configuration files!

## Getting Help

If you need to debug further:

```bash
# Collect all logs
docker compose logs > all-logs.txt

# Check specifically:
docker compose logs omejdn-ui > ui-logs.txt
docker compose logs daps > daps-logs.txt
docker compose logs nginx > nginx-logs.txt
```

Then review the logs for errors or share them for troubleshooting.
