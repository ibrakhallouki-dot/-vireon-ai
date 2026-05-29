from dataclasses import dataclass, field
from typing import Optional
import time

@dataclass
class VideoJob:
    job_id: str
    status: str = "queued"
    progress: int = 0
    error: Optional[str] = None
    result_url: Optional[str] = None
    created_at: float = field(default_factory=time.time)

class JobManager:
    def __init__(self):
        self._jobs: dict[str, VideoJob] = {}

    def create_job(self, job_id: str):
        self._jobs[job_id] = VideoJob(job_id=job_id)

    def get_job(self, job_id: str) -> Optional[VideoJob]:
        return self._jobs.get(job_id)

    def update_status(self, job_id: str, status: str, progress: int = None, error: str = None):
        job = self._jobs.get(job_id)
        if job:
            job.status = status
            if progress is not None:
                job.progress = progress
            if error is not None:
                job.error = error

    def set_result_url(self, job_id: str, url: str):
        job = self._jobs.get(job_id)
        if job:
            job.result_url = url

    def remove_job(self, job_id: str):
        self._jobs.pop(job_id, None)
