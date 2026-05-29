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
