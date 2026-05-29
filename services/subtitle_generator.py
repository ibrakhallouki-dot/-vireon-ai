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
