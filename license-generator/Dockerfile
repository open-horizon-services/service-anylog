FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
COPY src/license-server.py app.py

RUN apt-get -y update && \
    pip install --no-cache-dir -r requirements.txt && \
    mkdir -p /data

EXPOSE 8001

CMD ["gunicorn", "--bind", "0.0.0.0:8001", "--workers", "2", "--access-logfile", "-", "--error-logfile", "-", "app:app"]