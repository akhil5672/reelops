# syntax=docker/dockerfile:1
FROM python:3.12-slim AS build
WORKDIR /w
COPY requirements.txt .
RUN pip wheel --no-cache-dir -r requirements.txt -w /wheels

FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN useradd -u 10001 -r -s /usr/sbin/nologin app
COPY --from=build /wheels /wheels
RUN pip install --no-cache-dir /wheels/* && rm -rf /wheels
COPY --chown=10001 worker.py /app/
USER 10001
EXPOSE 9100
# exec form so SIGTERM reaches python (PID 1) and the worker drains cleanly
CMD ["python", "/app/worker.py"]
