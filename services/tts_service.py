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
