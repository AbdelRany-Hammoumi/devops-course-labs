import os
import psycopg
from flask import Flask, jsonify, request

app = Flask(__name__)
DB_URL = os.environ["DATABASE_URL"]


def init_schema():
    with psycopg.connect(DB_URL) as conn:
        conn.execute(
            "CREATE TABLE IF NOT EXISTS notes (id serial PRIMARY KEY, body text)"
        )


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
    body = (request.get_json() or {}).get("body", "")
    with psycopg.connect(DB_URL) as conn:
        new_id = conn.execute(
            "INSERT INTO notes (body) VALUES (%s) RETURNING id", (body,)
        ).fetchone()[0]
    return jsonify(id=new_id, body=body), 201


if __name__ == "__main__":
    init_schema()
    app.run(host="0.0.0.0", port=8080)
