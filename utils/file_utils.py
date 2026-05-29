import os
import shutil
import tempfile

def create_job_dir(job_id: str) -> str:
    base = os.path.join(tempfile.gettempdir(), "vireon_jobs", job_id)
    os.makedirs(base, exist_ok=True)
    return base

def ensure_dir(path: str):
    os.makedirs(path, exist_ok=True)

def cleanup_dir(path: str):
    try:
        if os.path.exists(path):
            shutil.rmtree(path)
    except Exception as e:
        pass
