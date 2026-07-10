# License Server Docker Setup

This service runs a small Flask API for recording license acceptances to a persistent CSV file.

## Files

Expected files:

```text
Dockerfile.license_server
docker-compose.license_server.yml
license-server.py
requirements.license_server.txt
```

The Dockerfile copies `license-server.py` into the container as `app.py` so Gunicorn can run it as `app:app`.

## Build and Start

Run from the directory containing `docker-compose.license_server.yml`:

```bash
docker compose -f docker-compose.yml up -d --build
```

## Check Container Status

```bash
docker compose -f docker-compose.yml ps
```

## View Logs

```bash
docker compose -f docker-compose.yml logs -f
```

## Health Check

From the Docker host:

```bash
curl http://localhost:8001/health
```
or 
```bash
curl http://[public_ip]:8001/health
```

Expected response:

```json
{"status":"ok"}
```

## Test License Acceptance Endpoint

```bash
curl -X POST http://localhost:8001/api/license-accept \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Roy",
    "company": "AnyLog",
    "email": "roy@example.com",
    "project": "test-project",
    "license_key": "abc123456789xyz",
    "timestamp": "2026-05-07T12:00:00Z"
  }'
```

Expected response:

```json
{"status":"accepted"}
```

## Persistent Data

License acceptances are written to a mounted shared directory on the host:

```text
./shared-license-data/license_acceptances.csv
```

This file remains available even if the container is restarted or rebuilt.

## Stop the Service

```bash
docker compose -f docker-compose.yml down
```

## Rebuild After Code Changes

```bash
docker compose -f docker-compose.yml up -d --build
```
