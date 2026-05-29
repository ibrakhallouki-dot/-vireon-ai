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
