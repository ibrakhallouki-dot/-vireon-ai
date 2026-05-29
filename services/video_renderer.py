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
