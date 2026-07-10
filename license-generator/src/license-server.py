from flask import Flask, request, jsonify
from datetime import datetime, timezone
import csv
import os

app = Flask(__name__)

DATA_DIR = os.environ.get("DATA_DIR", "/data")
LOG_FILE = os.path.join(DATA_DIR, "license_acceptances.csv")

FIELDS = ["name", "company", "email", "project", "license_key", "timestamp"]

os.makedirs(DATA_DIR, exist_ok=True)


@app.route("/api/license-accept", methods=["POST"])
def license_accept():
    data = request.get_json(force=True, silent=False)

    if data is None:
        return jsonify({"error": "Request body is not valid JSON"}), 400

    missing = [k for k in FIELDS if k not in data]
    if missing:
        return jsonify({"error": "Missing required fields", "missing": missing}), 400

    file_exists = os.path.isfile(LOG_FILE)

    with open(LOG_FILE, "a", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=FIELDS + ["received_at"],
            extrasaction="ignore"
        )

        if not file_exists:
            writer.writeheader()

        writer.writerow({
            **data,
            "received_at": datetime.now(timezone.utc).isoformat()
        })

    print(
        f"[{datetime.now(timezone.utc).isoformat()}] Accepted: "
        f"{data['name']} <{data['email']}> "
        f"({data['company']}) — {data['project']} — "
        f"key: {data['license_key'][:16]}...",
        flush=True
    )

    return jsonify({"status": "accepted"}), 201


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8001, debug=False)
