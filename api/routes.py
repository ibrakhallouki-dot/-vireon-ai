from fastapi import APIRouter, BackgroundTasks, HTTPException, Request
from fastapi.responses import FileResponse
from core.models import JobStatus, GenerateRequest, StatusResponse, ResultResponse
from core.orchestrator import Orchestrator
import uuid
import os

router = APIRouter()
orchestrator = Orchestrator()

@router.post("/generate-video", response_model=JobStatus)
async def generate_video(request: GenerateRequest, background_tasks: BackgroundTasks):
    if not request.prompt.strip():
        raise HTTPException(status_code=400, detail="Prompt cannot be empty")
    job_id = str(uuid.uuid4())
    orchestrator.create_job(job_id)
    background_tasks.add_task(orchestrator.run_pipeline, job_id, request.prompt)
    return JobStatus(job_id=job_id, status="queued", progress=0)

@router.get("/status/{job_id}", response_model=StatusResponse)
async def get_status(job_id: str):
    job = orchestrator.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    return StatusResponse(
        job_id=job_id,
        status=job.status,
        progress=job.progress,
        error=job.error
    )

@router.get("/result/{job_id}")
async def get_result(job_id: str, background_tasks: BackgroundTasks):
    job = orchestrator.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    if job.status != "completed":
        raise HTTPException(status_code=409, detail="Job not completed yet")
    if not job.result_url or not os.path.exists(job.result_url):
        raise HTTPException(status_code=500, detail="Result file not found")
    background_tasks.add_task(orchestrator.cleanup_job, job_id, delay=300)
    return FileResponse(job.result_url, media_type="video/mp4", filename="vireon_video.mp4")
