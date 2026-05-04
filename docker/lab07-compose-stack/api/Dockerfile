FROM python:3.12-alpine

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080

RUN adduser -D -u 1000 appuser
USER appuser

CMD ["python", "app.py"]
