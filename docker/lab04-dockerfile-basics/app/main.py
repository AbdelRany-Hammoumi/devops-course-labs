from flask import Flask, jsonify
import os

app = Flask(__name__)


@app.get("/")
def hello():
    return jsonify(message="hello from container", host=os.uname().nodename)


@app.get("/health")
def health():
    return jsonify(status="ok"), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
