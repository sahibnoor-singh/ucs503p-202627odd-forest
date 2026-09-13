# ============================================================
# CJP Audio Processing Microservice
# Contribution: Ridhima Gupta
#
# Accepts an MP4 video, extracts audio using FFmpeg,
# removes/separates background audio using Demucs,
# and returns the cleaned vocal audio for transcription.
# ============================================================

from flask import Flask, request, send_file, jsonify
import subprocess
import os
import sys
import uuid

app = Flask(__name__)

UPLOAD_FOLDER = "uploads"
OUTPUT_FOLDER = "outputs"

os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(OUTPUT_FOLDER, exist_ok=True)


@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "status": "Audio microservice is running"
    })


@app.route("/process", methods=["POST"])
def process_video():

    if "file" not in request.files:
        return jsonify({"error": "No video file provided"}), 400

    video = request.files["file"]

    if video.filename == "":
        return jsonify({"error": "Empty filename"}), 400

    unique_id = str(uuid.uuid4())

    video_path = os.path.join(
        UPLOAD_FOLDER,
        unique_id + ".mp4"
    )

    audio_path = os.path.join(
        UPLOAD_FOLDER,
        unique_id + ".mp3"
    )

    video.save(video_path)

    try:

        # ---------------------------------------
        # STEP 1: Extract audio from video
        # ---------------------------------------

        print("Extracting audio from video...")

        subprocess.run([
            "ffmpeg",
            "-y",
            "-i",
            video_path,
            "-vn",
            "-acodec",
            "mp3",
            audio_path
        ], check=True)

        print("Audio extracted successfully.")

        # ---------------------------------------
        # STEP 2: Demucs
        # ---------------------------------------

        print("Running Demucs...")

        subprocess.run([
            sys.executable,
            "-m",
            "demucs",
            "--two-stems=vocals",
            "-o",
            OUTPUT_FOLDER,
            audio_path
        ], check=True)

        print("Demucs completed successfully.")

        # ---------------------------------------
        # STEP 3: Locate vocals.wav
        # ---------------------------------------

        filename = os.path.splitext(
            os.path.basename(audio_path)
        )[0]

        vocals_path = os.path.join(
            OUTPUT_FOLDER,
            "htdemucs",
            filename,
            "vocals.wav"
        )

        if not os.path.exists(vocals_path):
            return jsonify({
                "error": "Demucs vocals output not found"
            }), 500

        print("Clean vocal audio ready.")

        # ---------------------------------------
        # Return cleaned audio
        # ---------------------------------------

        return send_file(
            vocals_path,
            mimetype="audio/wav",
            as_attachment=True,
            download_name="clean_audio.wav"
        )

    except subprocess.CalledProcessError as e:

        print("Processing error:", e)

        return jsonify({
            "error": "Audio processing failed",
            "details": str(e)
        }), 500

    except Exception as e:

        print("Unexpected error:", e)

        return jsonify({
            "error": str(e)
        }), 500


if __name__ == "__main__":

    print("======================================")
    print("   CJP AUDIO PROCESSING MICROSERVICE")
    print("======================================")
    print("Server running on port 5000")

    app.run(
        host="0.0.0.0",
        port=5000,
        debug=True
    )