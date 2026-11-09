FROM python:3.12-slim

WORKDIR /api
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

EXPOSE 8000
# el puerto se puede cambiar con PORT, que es la variable que usan los proveedores en la nube
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
