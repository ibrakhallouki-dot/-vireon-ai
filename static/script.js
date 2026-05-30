const API_BASE = window.location.origin;
const chatArea = document.getElementById('chatArea');
const promptInput = document.getElementById('promptInput');
const sendBtn = document.getElementById('sendBtn');
const statusBar = document.getElementById('statusBar');

sendBtn.addEventListener('click', () => handleSend());
promptInput.addEventListener('keypress', (e) => {
    if (e.key === 'Enter') handleSend();
});

document.addEventListener('click', (e) => {
    if (e.target.classList.contains('suggestion-btn')) {
        promptInput.value = e.target.textContent;
        handleSend();
    }
});

async function handleSend() {
    const prompt = promptInput.value.trim();
    if (!prompt) return;

    addMessage('user', prompt);
    promptInput.value = '';
    showStatus('⏳ جاري إنشاء الفيديو...');
    
    const loadingMsg = addMessage('bot', '<div class="progress-indicator"><div class="spinner"></div> جاري الاتصال بالخادم...</div>');

    try {
        const generateRes = await fetch(`${API_BASE}/generate-video`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ prompt: prompt })
        });
        
        if (!generateRes.ok) throw new Error('فشل الاتصال بالخادم');
        
        const { job_id } = await generateRes.json();
        updateLoadingMessage(loadingMsg, 'script_generated');

        let completed = false;
        while (!completed) {
            await new Promise(r => setTimeout(r, 3000));
            const statusRes = await fetch(`${API_BASE}/status/${job_id}`);
            const statusData = await statusRes.json();
            updateLoadingMessage(loadingMsg, statusData.status);

            if (statusData.status === 'completed') completed = true;
            if (statusData.status === 'failed') {
                updateLoadingMessage(loadingMsg, 'failed', statusData.error || 'خطأ غير معروف');
                hideStatus();
                return;
            }
        }

        updateLoadingMessage(loadingMsg, 'done');
        hideStatus();

        const resultRes = await fetch(`${API_BASE}/result/${job_id}`);
        const blob = await resultRes.blob();
        const videoUrl = URL.createObjectURL(blob);

        loadingMsg.querySelector('.content').innerHTML = `
            <p>✅ الفيديو جاهز!</p>
            <div class="video-result">
                <video controls autoplay src="${videoUrl}"></video>
                <br>
                <a href="${videoUrl}" class="download-btn" download="vireon_video.mp4">📥 تحميل الفيديو</a>
            </div>
        `;

    } catch (err) {
        updateLoadingMessage(loadingMsg, 'error', err.message);
        hideStatus();
    }
}

function addMessage(type, content) {
    const div = document.createElement('div');
    div.className = `message ${type}-message`;
    const avatar = type === 'bot' ? '🤖' : '😃';
    div.innerHTML = `<div class="avatar">${avatar}</div><div class="content">${content}</div>`;
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
        'done': '✅ الفيديو جاهز!',
        'failed': `❌ فشل: ${error}`,
        'error': `❌ خطأ: ${error}`
    };
    const text = messages[status] || `⏳ ${status}...`;
    element.querySelector('.content').innerHTML = `<div class="progress-indicator"><div class="spinner"></div> ${text}</div>`;
}

function showStatus(text) {
    statusBar.style.display = 'block';
    statusBar.textContent = text;
}

function hideStatus() {
    statusBar.style.display = 'none';
}
