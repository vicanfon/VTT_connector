# Local Development Troubleshooting

This guide helps you troubleshoot common issues when running the project locally.

## Issue: Getting Redirected to Omejdn When Accessing Other Services

### Symptoms
- Visiting `https://localhost/connector/` redirects to `https://localhost/` (Omejdn)
- Visiting `https://localhost/provider-ui/` redirects to root
- All nginx proxied paths redirect to the Omejdn UI

### Diagnosis

Run the diagnostic script to check container health:

```bash
./scripts/diagnose.sh
```

This will check:
- Container status
- Service logs
- Internal connectivity
- Nginx configuration validity

### Common Causes and Solutions

#### 1. Containers Not Running

**Check:**
```bash
docker compose ps
```

**Fix:**
```bash
# Start all services
docker compose up -d

# Or restart specific service
docker compose restart nginx connector
```

#### 2. Connector Service Not Responding

**Check logs:**
```bash
docker compose logs connector
docker compose logs nginx
```

**Common issues:**
- Connector failed to start due to missing configuration
- Database connection issues
- Certificate/keystore problems

**Fix:**
```bash
# Check if connector is accessible directly
curl http://localhost:8081/

# If this works but nginx proxy doesn't, it's an nginx config issue
```

#### 3. Nginx Configuration Issues

**Test nginx config:**
```bash
docker compose exec nginx nginx -t
```

**Common problems:**
- **HTTPS backend issue**: If nginx tries to connect to `https://connector:8081` but the connector only supports HTTP internally
  - Solution: Change `proxy_pass` to `http://connector:8081/` (already fixed in latest version)

- **SSL verification failure**: Nginx can't verify backend SSL certificates
  - Solution: Add `proxy_ssl_verify off;` (already added in latest version)

**Fix:**
```bash
# After config changes, reload nginx
docker compose restart nginx
```

#### 4. Port Conflicts

**Check if ports are in use:**
```bash
# Check common ports
sudo netstat -tulpn | grep -E ':(80|443|8081|5001|5002|8091|8092|5433)'

# Or with ss
sudo ss -tulpn | grep -E ':(80|443|8081|5001|5002|8091|8092|5433)'
```

**Fix:**
- Stop conflicting services
- Or modify docker-compose.yml to use different ports

#### 5. Certificate Issues

**Check certificates:**
```bash
ls -lh cert/
# Should show server.crt and server.key

# Verify certificate
openssl x509 -in cert/server.crt -text -noout | grep -E '(Subject|Issuer|Not)'
```

**Fix:**
```bash
# Regenerate certificates
./scripts/generate-local-certs.sh localhost

# Restart nginx
docker compose restart nginx
```

## Testing Service Accessibility

### Test Directly (Bypass Nginx)

These should work if containers are running:

```bash
# Connector
curl http://localhost:8081/
# Expected: Some response (not a redirect)

# Provider UI
curl http://localhost:8091/
# Expected: HTML response

# Consumer UI
curl http://localhost:8092/
# Expected: HTML response
```

### Test Via Nginx Proxy

```bash
# Connector (accept self-signed cert)
curl -k https://localhost/connector/
# Expected: Same response as direct access

# Provider UI
curl -k https://localhost/provider-ui/
# Expected: HTML response (not a redirect to root)
```

### Check Specific Issues

```bash
# Check if nginx can reach connector internally
docker compose exec nginx curl -v http://connector:8081/

# Check nginx error logs
docker compose logs nginx | grep -i error

# Check connector logs
docker compose logs connector | tail -50
```

## Step-by-Step Debugging Process

### Step 1: Verify All Containers Are Running

```bash
docker compose ps
```

All services should show "Up" status. If any are down:

```bash
# Check why it failed
docker compose logs [service-name]

# Try to restart
docker compose restart [service-name]

# If still failing, check config
docker compose config
```

### Step 2: Test Direct Access

```bash
# Test each service directly
curl http://localhost:8081/     # Connector
curl http://localhost:8091/     # Provider UI
curl http://localhost:8092/     # Consumer UI
curl http://localhost:5001/     # Registration backend
curl http://localhost:5002/     # Registration UI
```

If these work, the services are running fine. Issue is with nginx proxy.

### Step 3: Test Nginx Proxy

```bash
# Test from inside nginx container
docker compose exec nginx curl -v http://connector:8081/
docker compose exec nginx curl -v http://provider-ui:8000/
docker compose exec nginx curl -v http://consumer-ui:8000/
```

If these work, nginx can reach the services internally.

### Step 4: Test External Access Through Nginx

```bash
curl -k -v https://localhost/connector/ 2>&1 | grep -E '(HTTP|Location)'
```

Check the response:
- **200 OK**: Working correctly
- **301/302 redirect**: Check Location header to see where it's redirecting
- **502/503/504**: Backend not reachable
- **Connection refused**: Nginx not running

### Step 5: Check Nginx Configuration

```bash
# Validate syntax
docker compose exec nginx nginx -t

# Check which location block is matching
docker compose exec nginx cat /etc/nginx/nginx.conf | grep -A5 "location /"

# Verify cert mounts
docker compose exec nginx ls -lh /etc/cert/
```

## Quick Fixes

### Fix 1: Restart Everything

```bash
docker compose down
docker compose up -d
docker compose ps
docker compose logs -f
```

### Fix 2: Rebuild Nginx Container

```bash
docker compose down nginx
docker compose up -d --build nginx
```

### Fix 3: Update Configuration

```bash
# Pull latest changes
git pull origin claude/setup-local-development-011CUgAm2Vfn39HAjmb8DFmG

# Restart services
docker compose down
docker compose up -d
```

### Fix 4: Clear and Reset

```bash
# Stop everything
docker compose down -v

# Remove volumes (WARNING: deletes data)
docker volume prune

# Start fresh
docker compose up -d
```

## Configuration Check

Verify these settings in your files:

### docker-compose.yml

- Nginx should mount: `./cert:/etc/cert/`
- Nginx should mount: `./nginx.development.conf:/etc/nginx/nginx.conf`
- All `__HOST__` placeholders should be replaced with `localhost`

### nginx.development.conf

- `server_name localhost;`
- `ssl_certificate /etc/cert/server.crt;`
- `ssl_certificate_key /etc/cert/server.key;`
- Backend proxy_pass should use `http://` for internal services (not `https://`)

### .env

- `OMEJDN_DOMAIN="localhost"`

## Still Having Issues?

1. **Check container logs carefully:**
   ```bash
   docker compose logs -f | grep -i error
   ```

2. **Verify network connectivity:**
   ```bash
   docker network ls
   docker network inspect vtt_connector_local
   ```

3. **Check resource usage:**
   ```bash
   docker stats
   ```

4. **Try accessing services individually** to isolate the problem:
   - Start only nginx and connector: `docker compose up -d nginx connector connector-database`
   - Test if that works before adding other services

5. **Check browser console** for additional errors when accessing via browser

6. **Verify DNS resolution** inside containers:
   ```bash
   docker compose exec nginx nslookup connector
   docker compose exec nginx nslookup provider-ui
   ```

## Getting Help

When reporting issues, include:

1. Output of `docker compose ps`
2. Relevant logs: `docker compose logs nginx connector`
3. Output of diagnostic script: `./scripts/diagnose.sh`
4. What URL you're accessing and what happens
5. Any error messages from browser console
