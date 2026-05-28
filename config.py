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
