FROM python:3.12-slim

WORKDIR /app

# Install dependencies first for better layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY fabric_rti_mcp/ ./fabric_rti_mcp/
COPY server.py .

# Default environment variables for Container App deployment
ENV FABRIC_RTI_TRANSPORT=http
ENV FABRIC_RTI_HTTP_HOST=0.0.0.0
ENV FABRIC_RTI_HTTP_PORT=3000
ENV FABRIC_RTI_HTTP_PATH=/mcp
ENV FABRIC_RTI_STATELESS_HTTP=true

EXPOSE 3000

CMD ["python", "server.py"]
