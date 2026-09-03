# Multi-stage: la etapa "dependencias" instala en un prefix aislado
# (/instalado) para que la etapa final no cargue con la cache de pip ni
# con herramientas de compilacion. psycopg[binary] ya trae wheel
# precompilado para glibc, asi que no hace falta gcc en ninguna etapa,
# pero separar igual reduce capas y dejar rastros de la instalacion.

# ---------------------------------------------------------------- build
FROM python:3.11-slim AS dependencias
WORKDIR /app
ENV PIP_NO_CACHE_DIR=1
COPY requirements.txt ./
RUN pip install --no-cache-dir --prefix=/instalado -r requirements.txt

# -------------------------------------------------------------- runtime
FROM python:3.11-slim AS runtime
WORKDIR /app
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH=/usr/local/lib/python3.11/site-packages

# Usuario sin privilegios, igual que en los servicios Node.
RUN groupadd -r aroma && useradd -r -g aroma aroma

COPY --from=dependencias /instalado /usr/local
COPY app ./app

USER aroma

EXPOSE 4004
HEALTHCHECK --interval=10s --timeout=3s --retries=6 --start-period=20s \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:4004/salud').status==200 else 1)"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "4004"]
