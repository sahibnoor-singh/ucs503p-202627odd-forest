# ============================================================
# Project FOREST - Prototype API Demo
# ============================================================
# This is a simplified prototype API to demonstrate the
# backend architecture for the academic submission.
# Advanced proprietary logic and API keys have been removed.

from flask import Flask, jsonify

app = Flask(__name__)

@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "status": "FOREST Prototype API is running (Demo Mode)"
    })

@app.route("/api/process", methods=["POST"])
def demo_process():
    """
    Demo endpoint for receiving video requests.
    In the production environment, this routes to our Gemini Flash pipeline.
    """
    return jsonify({
        "message": "Upload received successfully.",
        "status": "pending_analysis"
    })

if __name__ == "__main__":
    print("Starting FOREST Demo API on port 5000...")
    app.run(host="0.0.0.0", port=5000)