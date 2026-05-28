#!/bin/bash

# إنشاء المجلدات
mkdir -p api core services utils

# إنشاء requirements.txt
cat > requirements.txt << 'REQEOF'
fastapi>=0.110
uvicorn[standard]>=0.27
python-dotenv>=1.0
pydantic-settings>=2.1
groq>=0.4
aiohttp>=3.9
aiofiles>=23.2
gTTS>=2.5
slowapi>=0.1.9
httpx>=0.27
REQEOF

# إنشاء .env.example
cat > .env.example << 'ENVEOF'
GROQ_API_KEY=your_groq_api_key
PEXELS_API_KEY=your_pexels_api_key
GEMINI_API_KEY=optional
ELEVENLABS_API_KEY=optional
BACKGROUND_MUSIC_PATH=optional/music.mp3
RATE_LIMIT=10/minute
ENVEOF

# إنشاء main.py
cat > main.py << 'MAINEOF'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from slowapi.util import get_remote_address
from api.routes import router
from config import settings
import uvicorn

app = FastAPI(title="Vireon AI", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

limiter = None
try:
    from slowapi import Limiter
    limiter = Limiter(key_func=get_remote_address, default_limits=[settings.rate_limit])
    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
    app.add_middleware(SlowAPIMiddleware)
except ImportError:
    pass

app.include_router(router)

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
MAINEOF

# إنشاء config.py
cat > config.py << 'CONFEOF'
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    groq_api_key: str
    pexels_api_key: str
    gemini_api_key: str = ""
    elevenlabs_api_key: str = ""
    background_music_path: str = ""
    rate_limit: str = "10/minute"

    model_config = {
        "env_file": ".env",
        "env_file_encoding": "utf-8",
        "extra": "ignore"
    }

settings = Settings()
CONFEOF

# إنشاء api/__init__.py
touch api/__init__.py

# إنشاء api/routes.py
cat > api/routes.py << 'APIROUTESEOF'
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
APIROUTESEOF

# إنشاء api/dependencies.py
touch api/dependencies.py

# إنشاء core/__init__.py
touch core/__init__.py

# إنشاء core/models.py
cat > core/models.py << 'MODELSEOF'
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
MODELSEOF

# إنشاء core/job_manager.py
cat > core/job_manager.py << 'JOBEOF'
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
JOBEOF

# إنشاء core/orchestrator.py
cat > core/orchestrator.py << 'ORCHEOF'
import asyncio
import shutil
import os
from core.job_manager import JobManager
from services.script_generator import ScriptGenerator
from services.scene_processor import SceneProcessor
from services.media_fetcher import MediaFetcher
from services.tts_service import TTSService
from services.video_renderer import VideoRenderer
from utils.file_utils import create_job_dir, cleanup_dir
from utils.logger import get_logger

logger = get_logger(__name__)

class Orchestrator:
    def __init__(self):
        self.job_manager = JobManager()
        self.script_generator = ScriptGenerator()
        self.scene_processor = SceneProcessor()
        self.media_fetcher = MediaFetcher()
        self.tts_service = TTSService()
        self.video_renderer = VideoRenderer()

    def create_job(self, job_id: str):
        self.job_manager.create_job(job_id)

    def get_job(self, job_id: str):
        return self.job_manager.get_job(job_id)

    async def run_pipeline(self, job_id: str, prompt: str):
        job_dir = None
        try:
            job_dir = create_job_dir(job_id)
            self.job_manager.update_status(job_id, "script_generated", progress=10)

            script = await self.script_generator.generate(prompt)
            processed_script = self.scene_processor.process(script)
            self.job_manager.update_status(job_id, "media_fetched", progress=30)

            media_paths = await self.media_fetcher.fetch_all(processed_script.scenes, job_dir)
            self.job_manager.update_status(job_id, "voice_generated", progress=60)

            audio_paths, actual_durations = await self.tts_service.generate_scenes_audio(
                processed_script.scenes, job_dir
            )
            for i, scene in enumerate(processed_script.scenes):
                scene.duration = actual_durations[i]

            self.job_manager.update_status(job_id, "rendering", progress=80)
            output_path = os.path.join(job_dir, "final.mp4")
            await self.video_renderer.render(
                processed_script.scenes,
                media_paths,
                audio_paths,
                output_path,
                title=processed_script.title,
                background_music=os.getenv("BACKGROUND_MUSIC_PATH", "")
            )

            self.job_manager.update_status(job_id, "completed", progress=100)
            self.job_manager.set_result_url(job_id, output_path)
        except Exception as e:
            logger.exception(f"Job {job_id} failed: {str(e)}")
            self.job_manager.update_status(job_id, "failed", error=str(e))
            if job_dir:
                cleanup_dir(job_dir)

    async def cleanup_job(self, job_id: str, delay: int = 300):
        await asyncio.sleep(delay)
        job = self.job_manager.get_job(job_id)
        if job and job.result_url:
            dir_path = os.path.dirname(job.result_url)
            cleanup_dir(dir_path)
            self.job_manager.remove_job(job_id)
ORCHEOF

# إنشاء services/__init__.py
touch services/__init__.py

# services/script_generator.py
cat > services/script_generator.py << 'SGEOPY'
import json
import groq
from core.models import ScriptOutput, Scene
from config import settings
from utils.logger import get_logger

logger = get_logger(__name__)

class ScriptGenerator:
    def __init__(self):
        self.client = groq.AsyncGroq(api_key=settings.groq_api_key)
        self.model = "llama3-8b-8192"

    async def generate(self, prompt: str) -> ScriptOutput:
        system_msg = """You are a viral video script writer. Convert the user's idea into a short-form vertical video script (TikTok/Shorts/Reels). Output STRICT JSON only, no other text.

The JSON must have:
- title (catchy viral title)
- duration (total seconds, between 15-45)
- scenes (array, 5-8 scenes). Each scene has:
  - text: short, punchy voiceover line (hook in first 3 seconds)
  - duration: approximate seconds for this scene (will be adjusted)
  - visual_prompt: short description of stock footage to match

Rules:
- Hook the viewer in the first 3 seconds
- Use emotional, high-energy language
- Short sentences only
- Each scene should have a clear visual idea"""

        messages = [
            {"role": "system", "content": system_msg},
            {"role": "user", "content": f"Video idea: {prompt}"}
        ]

        response = await self.client.chat.completions.create(
            model=self.model,
            messages=messages,
            temperature=0.7,
            response_format={"type": "json_object"}
        )
        content = response.choices[0].message.content.strip()
        try:
            data = json.loads(content)
            script = ScriptOutput(**data)
            if len(script.scenes) < 5 or len(script.scenes) > 8:
                raise ValueError("Scene count out of range")
            return script
        except Exception as e:
            logger.error(f"Failed to parse script JSON: {e}")
            return self._fallback_script(prompt)

    def _fallback_script(self, prompt: str) -> ScriptOutput:
        return ScriptOutput(
            title=f"Viral: {prompt[:50]}",
            duration=30,
            scenes=[
                Scene(text="You won't believe what happens next!", duration=5, visual_prompt="shocked person"),
                Scene(text="This changed everything.", duration=5, visual_prompt="amazing view"),
                Scene(text="Watch till the end.", duration=5, visual_prompt="suspense"),
                Scene(text="Mind-blowing reveal!", duration=5, visual_prompt="reveal moment"),
                Scene(text="Share this with everyone.", duration=5, visual_prompt="celebrating crowd"),
                Scene(text="Like and follow for more.", duration=5, visual_prompt="thumbs up")
            ]
        )
SGEOPY

# services/scene_processor.py
cat > services/scene_processor.py << 'SPEOF'
from core.models import ScriptOutput
from utils.logger import get_logger

logger = get_logger(__name__)

class SceneProcessor:
    def process(self, script: ScriptOutput) -> ScriptOutput:
        total_specified = sum(s.duration for s in script.scenes)
        target_duration = script.duration or 30
        if target_duration < 15:
            target_duration = 30
        if target_duration > 45:
            target_duration = 45

        if total_specified <= 0:
            per_scene = target_duration / len(script.scenes)
            for scene in script.scenes:
                scene.duration = round(per_scene, 2)
        else:
            factor = target_duration / total_specified
            for scene in script.scenes:
                scene.duration = round(scene.duration * factor, 2)

        for scene in script.scenes:
            if scene.duration < 2.0:
                scene.duration = 2.0

        while sum(s.duration for s in script.scenes) > target_duration:
            longest = max(script.scenes, key=lambda s: s.duration)
            longest.duration = round(longest.duration - 0.2, 2)

        return script
SPEOF

# services/media_fetcher.py
cat > services/media_fetcher.py << 'MEDIEEOF'
import os
import aiohttp
import aiofiles
from typing import List
from core.models import Scene
from config import settings
from utils.file_utils import ensure_dir
from utils.logger import get_logger

logger = get_logger(__name__)

class MediaFetcher:
    def __init__(self):
        self.pexels_api_key = settings.pexels_api_key
        self.video_url = "https://api.pexels.com/videos/search"
        self.photo_url = "https://api.pexels.com/v1/search"

    async def fetch_all(self, scenes: List[Scene], job_dir: str) -> List[str]:
        paths = []
        for idx, scene in enumerate(scenes):
            video_path = await self._download_video(scene.visual_prompt, job_dir, idx)
            if video_path:
                paths.append(video_path)
                continue
            image_path = await self._download_photo(scene.visual_prompt, job_dir, idx)
            if image_path:
                paths.append(image_path)
            else:
                paths.append("")
        return paths

    async def _download_video(self, query: str, job_dir: str, idx: int) -> str:
        headers = {"Authorization": self.pexels_api_key}
        params = {"query": query, "per_page": 1, "orientation": "portrait", "size": "medium"}
        async with aiohttp.ClientSession() as session:
            try:
                async with session.get(self.video_url, headers=headers, params=params) as resp:
                    if resp.status != 200:
                        return ""
                    data = await resp.json()
                    videos = data.get("videos", [])
                    if not videos:
                        return ""
                    best_file = None
                    for vf in videos[0]["video_files"]:
                        if vf["quality"] in ("hd", "sd"):
                            best_file = vf
                            break
                    if not best_file:
                        best_file = videos[0]["video_files"][0]
                    video_url = best_file["link"]
                    ext = os.path.splitext(video_url.split("?")[0])[1] or ".mp4"
                    output_path = os.path.join(job_dir, f"scene_{idx}_video{ext}")
                    await self._download_file(session, video_url, output_path)
                    return output_path
            except Exception as e:
                logger.error(f"Video download failed: {e}")
                return ""

    async def _download_photo(self, query: str, job_dir: str, idx: int) -> str:
        headers = {"Authorization": self.pexels_api_key}
        params = {"query": query, "per_page": 1, "orientation": "portrait"}
        async with aiohttp.ClientSession() as session:
            try:
                async with session.get(self.photo_url, headers=headers, params=params) as resp:
                    if resp.status != 200:
                        return ""
                    data = await resp.json()
                    photos = data.get("photos", [])
                    if not photos:
                        return ""
                    photo_url = photos[0]["src"]["original"]
                    ext = os.path.splitext(photo_url.split("?")[0])[1] or ".jpg"
                    output_path = os.path.join(job_dir, f"scene_{idx}_image{ext}")
                    await self._download_file(session, photo_url, output_path)
                    return output_path
            except Exception as e:
                logger.error(f"Photo download failed: {e}")
                return ""

    async def _download_file(self, session, url, dest):
        try:
            async with session.get(url) as resp:
                if resp.status == 200:
                    async with aiofiles.open(dest, "wb") as f:
                        await f.write(await resp.read())
        except Exception as e:
            logger.error(f"File download error {url}: {e}")
MEDIEEOF

# services/tts_service.py
cat > services/tts_service.py << 'TTSEOF'
import os
import asyncio
from typing import List, Tuple
from core.models import Scene
from utils.logger import get_logger
from gtts import gTTS

logger = get_logger(__name__)

class TTSService:
    def __init__(self):
        self.use_elevenlabs = bool(os.getenv("ELEVENLABS_API_KEY"))

    async def generate_scenes_audio(self, scenes: List[Scene], job_dir: str) -> Tuple[List[str], List[float]]:
        paths = []
        durations = []
        for idx, scene in enumerate(scenes):
            audio_path = os.path.join(job_dir, f"scene_{idx}_tts.mp3")
            duration = await self._generate_tts(scene.text, audio_path)
            paths.append(audio_path)
            durations.append(duration)
        return paths, durations

    async def _generate_tts(self, text: str, output_path: str) -> float:
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(None, self._sync_gtts, text, output_path)
        duration = await self._get_audio_duration(output_path)
        return duration

    def _sync_gtts(self, text: str, output_path: str):
        tts = gTTS(text=text, lang="en")
        tts.save(output_path)

    async def _get_audio_duration(self, file_path: str) -> float:
        try:
            cmd = [
                "ffprobe", "-v", "error", "-show_entries",
                "format=duration", "-of", "default=noprint_wrappers=1:nokey=1",
                file_path
            ]
            proc = await asyncio.create_subprocess_exec(*cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
            stdout, _ = await proc.communicate()
            return float(stdout.decode().strip())
        except Exception as e:
            logger.error(f"Failed to get duration for {file_path}: {e}")
            return 3.0
TTSEOF

# services/subtitle_generator.py
cat > services/subtitle_generator.py << 'SUBTITLEEOF'
import os
from typing import List
from core.models import Scene
from utils.logger import get_logger

logger = get_logger(__name__)

class SubtitleGenerator:
    def generate(self, scenes: List[Scene], output_ass_path: str, video_width=1080, video_height=1920):
        ass_header = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {video_width}
PlayResY: {video_height}
WrapStyle: 2

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,24,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,3,0,2,10,10,50,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
        events = ""
        start_time = 0.0
        for i, scene in enumerate(scenes):
            end_time = start_time + scene.duration
            start_ass = self._seconds_to_ass(start_time)
            end_ass = self._seconds_to_ass(end_time)
            text_with_fade = "{\\fad(200,200)}" + scene.text
            events += f"Dialogue: 0,{start_ass},{end_ass},Default,,0,0,0,,{text_with_fade}\n"
            start_time = end_time

        with open(output_ass_path, "w", encoding="utf-8") as f:
            f.write(ass_header + events)

    def _seconds_to_ass(self, seconds: float) -> str:
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        secs = int(seconds % 60)
        centiseconds = int((seconds - int(seconds)) * 100)
        return f"{hours:01d}:{minutes:02d}:{secs:02d}.{centiseconds:02d}"
SUBTITLEEOF

# services/video_renderer.py
cat > services/video_renderer.py << 'VIDEOEOF'
import os
import asyncio
from typing import List
from core.models import Scene
from services.subtitle_generator import SubtitleGenerator
from utils.logger import get_logger

logger = get_logger(__name__)

class VideoRenderer:
    def __init__(self):
        self.subtitle_generator = SubtitleGenerator()

    async def render(
        self,
        scenes: List[Scene],
        media_paths: List[str],
        audio_paths: List[str],
        output_path: str,
        title: str = "",
        background_music: str = ""
    ):
        os.makedirs(os.path.dirname(output_path), exist_ok=True)

        ass_path = output_path.replace(".mp4", ".ass")
        self.subtitle_generator.generate(scenes, ass_path)

        filter_complex = self._build_filter_complex(media_paths, audio_paths, scenes, ass_path, background_music)

        cmd = ["ffmpeg", "-y"]

        for path in media_paths:
            if path and os.path.exists(path):
                cmd.extend(["-i", path])
            else:
                cmd.extend(["-f", "lavfi", "-i", "color=c=black:s=1080x1920:d=5"])
        for path in audio_paths:
            cmd.extend(["-i", path])
        if background_music and os.path.exists(background_music):
            cmd.extend(["-stream_loop", "-1", "-i", background_music])

        cmd.extend(["-filter_complex", filter_complex])
        cmd.extend(["-map", "[video_out]", "-map", "[audio_out]"])
        cmd.extend([
            "-c:v", "libx264", "-preset", "fast", "-crf", "23",
            "-c:a", "aac", "-b:a", "128k",
            "-pix_fmt", "yuv420p",
            "-movflags", "+faststart",
            output_path
        ])

        logger.info(f"Running FFmpeg: {' '.join(cmd)}")
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await proc.communicate()
        if proc.returncode != 0:
            err_msg = stderr.decode()[-500:]
            logger.error(f"FFmpeg failed: {err_msg}")
            raise RuntimeError(f"FFmpeg error: {err_msg}")
        logger.info("Rendering completed successfully")

    def _build_filter_complex(self, media_paths, audio_paths, scenes, ass_path, bg_music_path):
        video_labels = []
        for i, (path, scene) in enumerate(zip(media_paths, scenes)):
            dur = scene.duration
            if path and os.path.exists(path) and not path.lower().endswith(('.jpg', '.jpeg', '.png')):
                video_labels.append(f"[{i}:v] trim=duration={dur}, setpts=PTS-STARTPTS, fps=25, scale=1080:1920:force_original_aspect_ratio=increase, crop=1080:1920, format=yuv420p [v{i}];")
            elif path and os.path.exists(path):
                total_frames = int(dur * 25)
                video_labels.append(f"[{i}:v] zoompan=z='min(zoom+0.0015,1.5)':d={total_frames}:s=1080x1920, fps=25, format=yuv420p, trim=duration={dur}, setpts=PTS-STARTPTS [v{i}];")
            else:
                video_labels.append(f"[{i}:v] trim=duration={dur}, setpts=PTS-STARTPTS, fps=25, format=yuv420p [v{i}];")

        crossfade_dur = 0.5
        current = "v0"
        offset = 0.0
        for i in range(1, len(video_labels)):
            offset += scenes[i-1].duration
            out_label = f"vt{i}"
            video_labels.append(f"[{current}][v{i}] xfade=transition=fade:duration={crossfade_dur}:offset={offset - crossfade_dur} [{out_label}];")
            current = out_label

        video_labels.append(f"[{current}] ass='{ass_path}' [video_out];")
        video_filter = "".join(video_labels)

        audio_inputs = "".join([f"[{len(media_paths)+i}:a]" for i in range(len(audio_paths))])
        audio_concat = f"{audio_inputs} concat=n={len(audio_paths)}:v=0:a=1 [tts_mixed];"

        if bg_music_path and os.path.exists(bg_music_path):
            bg_index = len(media_paths) + len(audio_paths)
            audio_mix = f"[tts_mixed][{bg_index}:a] amix=inputs=2:duration=first:dropout_transition=2, volume=0.7 [audio_out];"
            return video_filter + audio_concat + audio_mix

        return video_filter + audio_concat + "[tts_mixed] volume=1.0 [audio_out];"
VIDEOEOF

# إنشاء utils/__init__.py
touch utils/__init__.py

# utils/file_utils.py
cat > utils/file_utils.py << 'FILEUTILEOF'
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
FILEUTILEOF

# utils/logger.py
cat > utils/logger.py << 'LOGGEREOF'
import logging
import sys

def get_logger(name: str) -> logging.Logger:
    logger = logging.getLogger(name)
    if not logger.handlers:
        logger.setLevel(logging.INFO)
        handler = logging.StreamHandler(sys.stdout)
        formatter = logging.Formatter('[%(asctime)s] %(levelname)s %(name)s: %(message)s')
        handler.setFormatter(formatter)
        logger.addHandler(handler)
    return logger
LOGGEREOF

echo "✅ تم إنشاء جميع الملفات بنجاح. الآن ارفعها إلى GitHub."
