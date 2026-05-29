from pydantic import BaseModel, Field
from typing import List, Optional

class Scene(BaseModel):
    text: str
    duration: float
    visual_prompt: str

class ScriptOutput(BaseModel):
    title: str
    duration: float
    scenes: List[Scene]

class GenerateRequest(BaseModel):
    prompt: str

class JobStatus(BaseModel):
    job_id: str
    status: str
    progress: int = 0
    error: Optional[str] = None

class StatusResponse(BaseModel):
    job_id: str
    status: str
    progress: int
    error: Optional[str] = None

class ResultResponse(BaseModel):
    job_id: str
    video_url: str
