# ============================================================
# Audio Preprocessing - Demucs
# Contribution: Ridhima Gupta
#
# This module extracts audio from videos using FFmpeg
# and uses Demucs to separate vocals from background audio.
# The generated vocals.wav will be used in the next
# transcription stage.
# ============================================================

import os
import subprocess
import sys

VIDEO_FOLDER = "Videos"
AUDIO_FOLDER = "audio_files"
OUTPUT_FOLDER = "demucs_outputs"

os.makedirs(AUDIO_FOLDER, exist_ok=True)
os.makedirs(OUTPUT_FOLDER, exist_ok=True)

video_extensions = (".mp4", ".mov", ".mkv", ".avi")

videos = [
    f for f in os.listdir(VIDEO_FOLDER)
    if f.lower().endswith(video_extensions)
]

print(f"Found {len(videos)} videos.")

for i, video in enumerate(videos, 1):

    print("\n" + "=" * 60)
    print(f"[{i}/{len(videos)}] Processing: {video}")

    video_path = os.path.join(VIDEO_FOLDER, video)

    name = os.path.splitext(video)[0]
    mp3_path = os.path.join(AUDIO_FOLDER, name + ".mp3")

    # -----------------------------------------
    # STEP 1: Extract audio from video
    # -----------------------------------------

    print("Extracting audio...")

    try:
        subprocess.run([
            "ffmpeg",
            "-y",
            "-i", video_path,
            "-vn",
            "-acodec", "mp3",
            mp3_path
        ], check=True)

        print("Audio extracted successfully.")

    except Exception as e:
        print("Audio extraction failed:", e)
        continue

    # -----------------------------------------
    # STEP 2: Demucs
    # -----------------------------------------

    print("Running Demucs...")

    try:
        subprocess.run([
            sys.executable,
            "-m",
            "demucs",
            "--two-stems=vocals",
            "-o",
            OUTPUT_FOLDER,
            mp3_path
        ], check=True)

        print("Demucs completed successfully.")

    except Exception as e:
        print("Demucs failed:", e)
        continue

    print(f"Finished: {video}")

print("\n" + "=" * 60)
print("ALL VIDEOS PROCESSED!")
print(f"Demucs outputs are in: {OUTPUT_FOLDER}")
