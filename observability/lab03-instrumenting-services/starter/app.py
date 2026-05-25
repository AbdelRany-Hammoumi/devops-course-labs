"""
Minimal Flask "orders" service. Intentionally has a ~5% error rate to make alerts fire.

TODO list (see lab README for details and slide pointers):
  1. Add a Counter   http_requests_total{method, route, status}     -- chapter slide "Prometheus Client - Python"
  2. Add a Histogram http_request_duration_seconds{method, route}    -- chapter slide "Choosing Histogram Buckets"
  3. Expose /metrics endpoint with generate_latest()                 -- chapter slide "Prometheus Client - Python"
  4. Replace print(...) with a structured JSON logger; include       -- chapter slide "Structured Logs"
     request_id (from X-Request-ID header, generate if missing)
"""
import os
import random
import time
import uuid

from flask import Flask, jsonify, request

# TODO 1+2: import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
# from prometheus_client import ...

# TODO 4: replace `print` with a structured JSON logger.
# from pythonjsonlogger import jsonlogger
# import logging
# (see lab README step 3)

app = Flask(__name__)

# TODO 1: declare REQ_COUNT here
# TODO 2: declare REQ_LATENCY here


@app.before_request
def _start_timer():
    request._start = time.perf_counter()
    # TODO 4: read X-Request-ID header; generate uuid if absent; store on request


@app.after_request
def _record_metrics(resp):
    elapsed = time.perf_counter() - request._start
    # TODO 1: increment REQ_COUNT with (method, endpoint, status_code)
    # TODO 2: observe REQ_LATENCY with (method, endpoint) and elapsed
    # TODO 4: log one structured line with route, status, elapsed_ms, request_id
    print(  # noqa: T201  (TODO 4: replace this print with the structured logger)
        f"{request.method} {request.endpoint} {resp.status_code} {elapsed*1000:.1f}ms"
    )
    return resp


@app.route("/orders", methods=["GET"])
def list_orders():
    # Simulate work + a ~5% failure rate
    time.sleep(random.uniform(0.01, 0.150))
    if random.random() < 0.05:
        return jsonify(error="db unreachable"), 500
    return jsonify(orders=[{"id": 1}, {"id": 2}, {"id": 3}])


@app.route("/orders", methods=["POST"])
def place_order():
    time.sleep(random.uniform(0.02, 0.300))
    if random.random() < 0.05:
        return jsonify(error="payment declined"), 500
    return jsonify(order={"id": str(uuid.uuid4())[:8]}), 201


@app.route("/healthz")
def healthz():
    return "ok", 200


# TODO 3: add an /metrics endpoint returning Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
