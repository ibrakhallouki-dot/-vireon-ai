const chatArea = document.getElementById('chatArea');
const promptInput = document.getElementById('promptInput');
const sendBtn = document.getElementById('sendBtn');
const statusBar = document.getElementById('statusBar');

// أرسل الفكرة عند الضغط على زر الإرسال
sendBtn.addEventListener('click', () => handleSend());
// أرسل الفكرة عند الضغط على Enter
promptInput.addEventListener('keypress', (e) => {
    if (e.key === 'Enter') handleSend();
});

// اقتراحات سريعة
document.addEventListener('click', (e) => {
    if (e.target.classList.contains('suggestion-btn')) {
        promptInput.value = e.target.textContent;
        handleSend();
    }
});

async function handleSend() {
    const prompt = promptInput.value.trim();
    if (!prompt) return;

    // إظهار رسالة المستخدم
    addMessage('user', prompt);
    promptInput.value = '';

    // إظهار رسالة انتظار
    showStatus('⏳ جاري إنشاء الفيديو...');
    const loadingMsg = addMessage('bot', '<div class="progress-indicator"><div class="spinner"></div> جاري إنشاء النص...</div>');

    try {
        // 1. أرسل الطلب لإنشاء الفيديو
        const generateRes = await fetch('/generate-video', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ prompt: prompt })
        });
        const { job_id } = await generateRes.json();

        // 2. تابع الحالة
        let completed = false;
        while (!completed) {
            await new Promise(r => setTimeout(r, 3000)); // انتظر 3 ثوان

            const statusRes = await fetch(`/status/${job_id}`);
            const statusData = await statusRes.json();

            // حدث رسالة التحميل
            updateLoadingMessage(loadingMsg, statusData.status);

            if (statusData.status === 'completed') {
                completed = true;
            } else if (statusData.status === 'failed') {
                updateLoadingMessage(loadingMsg, 'failed', statusData.error);
                hideStatus();
                return;
            }
        }

        // 3. الفيديو جاهز
        updateLoadingMessage(loadingMsg, 'done');
        hideStatus();

        // 4. احصل على رابط الفيديو
        const resultRes = await fetch(`/result/${job_id}`);
        const blob = await resultRes.blob();
        const videoUrl = URL.createObjectURL(blob);

        // 5. عرض الفيديو في الشات
        addMessage('bot', `
            <p>✅ الفيديو جاهز!</p>
            <div class="video-result">
                <video controls autoplay src="${videoUrl}"></video>
                <br>
                <a href="${videoUrl}" class="download-btn" download="vireon_video.mp4">📥 تحميل الفيديو</a>
            </div>
        `);

    } catch (err) {
        updateLoadingMessage(loadingMsg, 'error', err.message);
        hideStatus();
    }
}

function addMessage(type, content) {
    const div = document.createElement('div');
    div.className = `message ${type}-message`;

    const avatar = type === 'bot' ? '🤖' : '😃';
    div.innerHTML = `
        <div class="avatar">${avatar}</div>
        <div class="content">${content}</div>
    `;

    chatArea.appendChild(div);
    chatArea.scrollTop = chatArea.scrollHeight;
    return div;
}

function updateLoadingMessage(element, status, error = '') {
    const messages = {
        'queued': '🔍 في قائمة الانتظار...',
        'script_generated': '📝 تم إنشاء النص...',
        'media_fetched': '🎬 جاري جمع المقاطع...',
        'voice_generated': '🎤 جاري توليد الصوت...',
        'rendering': '🎥 جاري تركيب الفيديو...',
        'completed': '✅ تم الانتهاء!',
        'done': '✅ الفيديو جاهز!',
        'failed': `❌ فشل: ${error}`,
        'error': `❌ خطأ: ${error}`
    };

    const text = messages[status] || `⏳ ${status}...`;
    element.querySelector('.content').innerHTML = `
        <div class="progress-indicator">
            <div class="spinner"></div> ${text}
        </div>
    `;
}

function showStatus(text) {
    statusBar.style.display = 'block';
    statusBar.textContent = text;
}

function hideStatus() {
    statusBar.style.display = 'none';
}
