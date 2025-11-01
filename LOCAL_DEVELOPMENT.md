# Local Development Guide

This guide helps you run the VTT Connector project on your laptop for local development.

## Quick Start

```bash
# Clone the repository with the local development branch
git clone -b claude/setup-local-development-011CUgAm2Vfn39HAjmb8DFmG https://github.com/vicanfon/VTT_connector.git
cd VTT_connector

# Start all services
docker compose up -d

# Check if all containers are running
docker compose ps

# View logs if needed
docker compose logs -f
```

## Service Access URLs

### Main Services (via HTTPS Reverse Proxy)

| Service | URL | Description |
|---------|-----|-------------|
| **DAPS/Omejdn** | `https://localhost/` | Authentication service (default landing page) |
| **Connector API** | `https://localhost/connector/` | Data Space Connector API |
| **Connector Swagger** | `https://localhost/connector/api/docs` | API documentation |
| **Broker Infrastructure** | `https://localhost/broker/infrastructure/` | Broker infrastructure endpoint |
| **Broker Catalog** | `https://localhost/broker/catalog/` | Broker catalog |
| **Broker Fuseki** | `https://localhost/broker/fuseki/` | SPARQL endpoint |
| **Provider UI** | `https://localhost/provider-ui/` | Provider user interface |
| **Consumer UI** | `https://localhost/consume/` | Consumer user interface |
| **Connector Registration** | `https://localhost/connector-registration/` | Registration backend |
| **Connector Registration UI** | `https://localhost/connector-registration-user-interface/` | Registration frontend |

### Direct Port Access (bypassing nginx)

| Service | URL | Description |
|---------|-----|-------------|
| **Connector** | `http://localhost:8081` | Direct connector access |
| **Provider UI** | `http://localhost:8091` | Direct provider UI access |
| **Consumer UI** | `http://localhost:8092` | Direct consumer UI access |
| **Connector Registration** | `http://localhost:5001` | Direct registration backend |
| **Connector Registration UI** | `http://localhost:5002` | Direct registration UI |
| **PostgreSQL** | `localhost:5433` | Database (user: postgresuserb, password: password) |

## Default Landing Page

When you visit `https://localhost/`, you'll see the **Omejdn (DAPS)** authentication interface. This is expected behavior as Omejdn serves as the identity provider for the data space.

**To access other services**, use the specific paths listed above.

## SSL Certificate Warning

Since we're using self-signed certificates for local development, your browser will show a security warning. This is normal for local development:

1. Click "Advanced" or "Details"
2. Click "Proceed to localhost (unsafe)" or similar option
3. The certificate warning appears because it's self-signed, not from a trusted authority

## Authentication

Default credentials for Omejdn admin:
- **Username**: `admin`
- **Password**: `admin` (⚠️ Change this in production!)

These are set in the `.env` file.

## Common Commands

```bash
# Start services
docker compose up -d

# Stop services
docker compose down

# View logs for all services
docker compose logs -f

# View logs for specific service
docker compose logs -f nginx
docker compose logs -f connector

# Restart a specific service
docker compose restart nginx

# Rebuild and restart
docker compose up -d --build

# Check service status
docker compose ps
```

## Regenerating SSL Certificates

If you need to regenerate the self-signed certificates:

```bash
./scripts/generate-local-certs.sh localhost
```

Or for a different hostname:

```bash
./scripts/generate-local-certs.sh myhost.local
```

## Troubleshooting

### Container won't start
```bash
# Check logs
docker compose logs [service-name]

# Check if ports are already in use
netstat -tulpn | grep -E ':(80|443|8081|5001|5002|8091|8092|5433)'

# Restart services
docker compose restart
```

### Nginx certificate errors
- Make sure `cert/server.crt` and `cert/server.key` exist
- Regenerate certificates using the script above
- Check docker-compose.yml mounts `./cert:/etc/cert/`

### Can't access services
- Verify containers are running: `docker compose ps`
- Check if all containers show "Up" status
- View logs: `docker compose logs -f`

### Database connection issues
- Make sure postgres container is running
- Check connection: `psql -h localhost -p 5433 -U postgresuserb -d connectorbdb`

## Environment Configuration

Key configuration files:
- `.env` - Environment variables and credentials
- `docker-compose.yml` - Service definitions
- `nginx.development.conf` - Reverse proxy configuration
- `conf/config.json` - Connector configuration

## Next Steps

1. **Start the services**: `docker compose up -d`
2. **Access Omejdn**: Visit `https://localhost/` and accept the certificate warning
3. **Test the Connector**: Visit `https://localhost/connector/api/docs`
4. **Use Provider UI**: Visit `https://localhost/provider-ui/`
5. **Use Consumer UI**: Visit `https://localhost/consume/`

## Production Deployment

⚠️ **This configuration is for LOCAL DEVELOPMENT ONLY!**

For production deployment:
- Use valid SSL certificates from a trusted CA
- Change default passwords in `.env`
- Use the production FQDN instead of localhost
- Review security settings
- See the main `README.md` for production deployment instructions

## Support

For issues or questions:
- Check `TROUBLESHOOTING.md`
- Review container logs
- Check the main `README.md`
