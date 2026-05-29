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
