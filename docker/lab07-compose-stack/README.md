# Lab 7 — Compose Stack

## Objectives

- Author a `compose.yaml` describing a Flask API + Postgres stack
- Use a healthcheck on Postgres + `depends_on: condition: service_healthy`
- Add a `compose.override.yaml` for a dev hot-reload workflow (bind mount)
- Use a `profile` to gate an optional debug tool
- Manage the stack with `docker compose up/down/logs/exec`

## Prerequisites

- Labs 04 and 06 completed
- Docker Engine ≥ 29.4 (Compose v2 is built in: `docker compose version`)
- Free TCP port `8080`

## Duration

~ 30 minutes

## Context

You will build a tiny Flask API with one endpoint (`POST /notes`, `GET /notes`) that persists to Postgres. The lab walks you through the Compose file in three iterations: minimal → with healthcheck → with override.

## Starter Code

```
lab07-compose-stack/
├── api/
│   ├── Dockerfile
│   ├── requirements.txt
│   └── app.py
└── README.md
```

The `api/app.py`:

```python
import os
import psycopg
from flask import Flask, jsonify, request

app = Flask(__name__)
DB_URL = os.environ["DATABASE_URL"]

def init_schema():
    with psycopg.connect(DB_URL) as conn:
        conn.execute("CREATE TABLE IF NOT EXISTS notes (id serial PRIMARY KEY, body text)")

@app.get("/health")
def health():
    return jsonify(status="ok")

@app.get("/notes")
def list_notes():
    with psycopg.connect(DB_URL) as conn:
        rows = conn.execute("SELECT id, body FROM notes ORDER BY id").fetchall()
    return jsonify([{"id": r[0], "body": r[1]} for r in rows])

@app.post("/notes")
def create_note():
    body = request.get_json().get("body", "")
    with psycopg.connect(DB_URL) as conn:
        new_id = conn.execute(
            "INSERT INTO notes (body) VALUES (%s) RETURNING id", (body,)
        ).fetchone()[0]
    return jsonify(id=new_id, body=body), 201

if __name__ == "__main__":
    init_schema()
    app.run(host="0.0.0.0", port=8080)
```

The `api/requirements.txt`:

```
flask==3.0.3
psycopg[binary]==3.2.3
```

The `api/Dockerfile`:

```dockerfile
FROM python:3.12-alpine
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8080
RUN adduser -D -u 1000 appuser
USER appuser
CMD ["python", "app.py"]
```

## Instructions

### Step 1 — A minimal compose.yaml

Create `compose.yaml` at the lab root:

```yaml
services:
  db:
    image: postgres:17-alpine
    environment:
      POSTGRES_PASSWORD: secret
      POSTGRES_DB: lab
    volumes:
      - pgdata:/var/lib/postgresql/data

  api:
    build: ./api
    image: lab07-api:0.1.0
    environment:
      DATABASE_URL: postgres://postgres:secret@db:5432/lab
    ports:
      - "8080:8080"
    depends_on:
      - db

volumes:
  pgdata:
```

Bring it up:

```bash
docker compose up -d
docker compose ps
```

Try a few requests:

```bash
curl -X POST http://localhost:8080/notes \
  -H "Content-Type: application/json" \
  -d '{"body":"first note"}'
curl http://localhost:8080/notes
```

You may see the api container restart 1–3 times because Postgres is not ready yet — `depends_on` without a condition only waits for the container to start, not for the database to accept queries. We fix that in step 2.

```bash
docker compose logs api | grep -i "could not connect" | head -3
```

### Step 2 — Add a healthcheck and gate the api on it

Update `compose.yaml`:

```yaml
services:
  db:
    image: postgres:17-alpine
    environment:
      POSTGRES_PASSWORD: secret
      POSTGRES_DB: lab
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d lab"]
      interval: 5s
      timeout: 3s
      retries: 5
      start_period: 5s

  api:
    build: ./api
    image: lab07-api:0.1.0
    environment:
      DATABASE_URL: postgres://postgres:secret@db:5432/lab
    ports:
      - "8080:8080"
    depends_on:
      db:
        condition: service_healthy

volumes:
  pgdata:
```

Re-create the stack from scratch and watch the api wait until db is healthy:

```bash
docker compose down
docker compose up -d
docker compose ps
# db   ... Up 5s (healthy)
# api  ... Up 1s
```

Verify no more "could not connect" errors:

```bash
docker compose logs api | grep -i "could not connect" || echo "no startup errors"
```

### Step 3 — Add a dev override with bind mount

Create `compose.override.yaml`:

```yaml
services:
  api:
    volumes:
      - ./api:/app
    environment:
      FLASK_DEBUG: "1"
```

The override is loaded automatically. Restart only the api service so it picks up the bind mount:

```bash
docker compose up -d --force-recreate api
docker compose exec api ls /app          # files come from your host, not the image
```

Edit `api/app.py` on your host (e.g. add a comment to the response). The change is visible inside the container immediately:

```bash
docker compose exec api cat /app/app.py | head -3
```

Note: this is a true bind mount. To get hot reload at the Python level you'd add `--reload` to `flask run`. For this lab we just demonstrate the file-sync.

### Step 4 — Add an optional debug tool with a profile

Append to `compose.yaml`:

```yaml
  pgadmin:
    image: dpage/pgadmin4:8
    environment:
      PGADMIN_DEFAULT_EMAIL: admin@example.com
      PGADMIN_DEFAULT_PASSWORD: admin
      PGADMIN_CONFIG_SERVER_MODE: "False"
    ports:
      - "5050:80"
    profiles: ["tools"]
```

Default `up` does NOT start pgadmin:

```bash
docker compose up -d
docker compose ps      # only db and api
```

Explicitly request the profile:

```bash
docker compose --profile tools up -d
docker compose ps      # db, api, pgadmin
```

### Step 5 — Day-to-day commands

Practice the daily-driver Compose CLI:

```bash
docker compose ps
docker compose logs -f api          # Ctrl-C to detach
docker compose exec api sh
# inside: env | grep DATABASE_URL ; exit

docker compose restart api
docker compose pull                  # pull new versions for image-only services
docker compose build api             # rebuild after Dockerfile change
docker compose config                # show merged + interpolated yaml
```

### Step 6 — Persistence test

Insert data, destroy containers, re-create:

```bash
curl -X POST http://localhost:8080/notes \
  -H "Content-Type: application/json" \
  -d '{"body":"compose persistence works"}'
curl http://localhost:8080/notes

docker compose down                 # stops containers, KEEPS volumes
docker compose up -d
sleep 5
curl http://localhost:8080/notes    # the note is still there
```

### Step 7 — Clean up

```bash
docker compose --profile tools down -v   # -v drops the volume too
docker compose ps -a                      # nothing
docker images lab07-api -q | xargs -r docker rmi
```

## Validation

```bash
docker compose ps -q
```
Expected: empty.

```bash
docker volume ls --filter name=lab07-compose-stack_pgdata --format '{{.Name}}'
```
Expected: empty.

```bash
docker network ls --filter name=lab07-compose-stack --format '{{.Name}}'
```
Expected: empty.

## Going Further (optional)

- Add a healthcheck for the api service that hits `/health`. Watch `docker compose ps` show `(healthy)`.
- Convert the api Dockerfile to multi-stage (lessons from chapter 05). What's the final image size?
- Create `compose.prod.yaml` that overrides the api to use the published image instead of `build:`. Run with `-f compose.yaml -f compose.prod.yaml up -d`.
- Move the Postgres password to a `secrets:` file. Mount as `/run/secrets/db_pwd`. Read it from the api with the `_FILE` env-var pattern.
- Add a second api replica with `deploy.replicas: 2` and put nginx in front as a load balancer. (Note: `deploy:` is mostly Swarm/K8s, but works partially in Compose.)
