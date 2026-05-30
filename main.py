from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles        # 🔵 أضف هذا السطر في الأعلى
from fastapi.responses import FileResponse         # 🔵 أضف هذا السطر في الأعلى
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

# إضافة خدمة الملفات الثابتة للواجهة الجميلة      # 🔵 أضف من هنا
app.mount("/static", StaticFiles(directory="static"), name="static")

@app.get("/")
async def chat_page():
    return FileResponse("static/index.html")
# ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬ # 🔵 إلى هنا

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
