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
