#!/usr/bin/env python3
# Composites real app screenshots into the marketing frames (App Store dims),
# with translated marketing copy per target language.
import base64, os, subprocess, sys, html

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SHOTS = os.environ.get("SHOTS_DIR", "/tmp/rclone-shots")          # /tmp/rclone-shots/<device>/<en|fr>/NN_id.png
OUT   = os.environ.get("FRAMES_DIR", "/tmp/rclone-frames")         # /tmp/rclone-frames/<device>/<lang>/NN_id.png
SRGB_PROFILE = "/System/Library/ColorSync/Profiles/sRGB Profile.icc"

PALETTES = {
    "violet":   dict(a="#F4EEFE", b="#E8DCFA", accent="#7C3AED", dark=False),
    "cream":    dict(a="#FBF7EE", b="#F2E7CC", accent="#7C3AED", dark=False),
    "midnight": dict(a="#1A1530", b="#0E0820", accent="#A78BFA", dark=True),
    "ocean":    dict(a="#E6F0FB", b="#CFE0F4", accent="#0E5FAE", dark=False),
    "forest":   dict(a="#E7F2EC", b="#CFE5D7", accent="#1F8F4A", dark=False),
    "rose":     dict(a="#FBECEF", b="#F4D5DC", accent="#C44569", dark=False),
}

# screen id -> palette, decor, screenshot basename
SCREENS = [
    ("crypt-first", "violet",   "lock",    "01_remotes"),
    ("backends",    "ocean",    "cloud",   "02_wizard"),
    ("crypt-paths", "violet",   "lock",    "03_folder"),
    ("stream",      "rose",     "sparkle", "04_file"),
    ("home",        "cream",    "sparkle", "05_home"),
    ("wizard",      "forest",   "cloud",   "06_import"),
    ("photos",      "rose",     "cloud",   "07_photos"),
    ("privacy",     "midnight", "lock",    "08_security"),
]

# Marketing copy: lang -> screen_id -> (headline_with_\n, subline)
LIST = "S3, R2, Drive, Dropbox, B2, SFTP, WebDAV, Storj, Wasabi…"
COPY = {
 "en": {
  "crypt-first": ("Every cloud.\nEncrypted.", "Native rclone crypt. Your keys never leave the iPhone."),
  "backends":    ("80+ services.\nOne home.", LIST),
  "crypt-paths": ("Filenames decrypted\non the fly.", "No cleartext in transit. AES-256 + NaCl secretbox."),
  "stream":      ("Stream direct.\nNo full download.", "Photos, video, PDF — opened straight from Files."),
  "home":        ("Your control\ncenter.", "Transfers, pins, photo sync, throughput. At a glance."),
  "wizard":      ("Guided\nsetup.", "OAuth in two taps. rclone.conf import in one gesture."),
  "photos":      ("Smart photo\nbackup.", "Adaptive throttle, network resume, background tasks."),
  "privacy":     ("Zero trackers.\nZero servers.", "No analytics. Open source. Strict ATS, TLS 1.3 everywhere."),
 },
 "fr": {
  "crypt-first": ("Tous vos clouds.\nChiffrés.", "rclone crypt natif. Vos clés ne quittent jamais l’iPhone."),
  "backends":    ("80+ services.\nUn seul endroit.", LIST),
  "crypt-paths": ("Noms déchiffrés\nà la volée.", "Aucun transit en clair. AES-256 + NaCl secretbox."),
  "stream":      ("Stream direct.\nZéro téléchargement.", "Photos, vidéos, PDF — ouverts depuis Fichiers iOS."),
  "home":        ("Votre centre\nde contrôle.", "Transferts, favoris, sync photo, débit. En un coup d’œil."),
  "wizard":      ("Assistant\nguidé.", "OAuth en deux tapotements. Import rclone.conf en un geste."),
  "photos":      ("Backup photo,\nintelligent.", "Throttle adaptatif, reprise réseau, exécution en arrière-plan."),
  "privacy":     ("Zéro tracker.\nZéro serveur.", "Aucune analytics. Open source. ATS strict, TLS 1.3 partout."),
 },
 "de": {
  "crypt-first": ("Jede Cloud.\nVerschlüsselt.", "Natives rclone crypt. Deine Schlüssel verlassen nie das iPhone."),
  "backends":    ("80+ Dienste.\nEin Zuhause.", LIST),
  "crypt-paths": ("Dateinamen sofort\nentschlüsselt.", "Kein Klartext bei der Übertragung. AES-256 + NaCl secretbox."),
  "stream":      ("Direkt streamen.\nKein Download.", "Fotos, Videos, PDF — direkt aus „Dateien“ geöffnet."),
  "home":        ("Deine\nKommandozentrale.", "Transfers, Favoriten, Foto-Sync, Tempo. Auf einen Blick."),
  "wizard":      ("Geführte\nEinrichtung.", "OAuth mit zwei Taps. rclone.conf-Import mit einer Geste."),
  "photos":      ("Cleveres\nFoto-Backup.", "Adaptive Drosselung, Netz-Wiederaufnahme, Hintergrund-Tasks."),
  "privacy":     ("Null Tracker.\nNull Server.", "Keine Analytics. Open Source. Striktes ATS, TLS 1.3 überall."),
 },
 "es": {
  "crypt-first": ("Todas tus nubes.\nCifradas.", "rclone crypt nativo. Tus claves nunca salen del iPhone."),
  "backends":    ("Más de 80 servicios.\nUn solo lugar.", LIST),
  "crypt-paths": ("Nombres descifrados\nal instante.", "Sin texto plano en tránsito. AES-256 + NaCl secretbox."),
  "stream":      ("Reproduce directo.\nSin descargas.", "Fotos, vídeo, PDF: abiertos desde Archivos."),
  "home":        ("Tu centro\nde control.", "Transferencias, favoritos, sync de fotos, velocidad. De un vistazo."),
  "wizard":      ("Configuración\nguiada.", "OAuth en dos toques. Importa rclone.conf con un gesto."),
  "photos":      ("Copia de fotos\ninteligente.", "Límite adaptable, reanudación de red, tareas en segundo plano."),
  "privacy":     ("Cero rastreadores.\nCero servidores.", "Sin analítica. Código abierto. ATS estricto, TLS 1.3 en todo."),
 },
 "it": {
  "crypt-first": ("Ogni cloud.\nCriptato.", "rclone crypt nativo. Le tue chiavi non lasciano mai l’iPhone."),
  "backends":    ("80+ servizi.\nUn solo posto.", LIST),
  "crypt-paths": ("Nomi decriptati\nal volo.", "Nessun testo in chiaro in transito. AES-256 + NaCl secretbox."),
  "stream":      ("Streaming diretto.\nNiente download.", "Foto, video, PDF — aperti da File."),
  "home":        ("Il tuo centro\ndi controllo.", "Trasferimenti, preferiti, sync foto, velocità. A colpo d’occhio."),
  "wizard":      ("Configurazione\nguidata.", "OAuth in due tap. Importa rclone.conf con un gesto."),
  "photos":      ("Backup foto\nintelligente.", "Limite adattivo, ripresa di rete, attività in background."),
  "privacy":     ("Zero tracker.\nZero server.", "Nessuna analitica. Open source. ATS rigido, TLS 1.3 ovunque."),
 },
 "ko": {
  "crypt-first": ("모든 클라우드.\n암호화.", "네이티브 rclone crypt. 키는 절대 iPhone을 벗어나지 않습니다."),
  "backends":    ("80개 이상 서비스.\n한 곳에서.", LIST),
  "crypt-paths": ("파일 이름을\n즉시 복호화.", "전송 중 평문 없음. AES-256 + NaCl secretbox."),
  "stream":      ("바로 스트리밍.\n다운로드 없이.", "사진, 동영상, PDF — 파일 앱에서 바로 열기."),
  "home":        ("나만의\n관제 센터.", "전송, 즐겨찾기, 사진 동기화, 속도를 한눈에."),
  "wizard":      ("가이드\n설정.", "두 번의 탭으로 OAuth. 한 동작으로 rclone.conf 가져오기."),
  "photos":      ("스마트\n사진 백업.", "적응형 속도 제한, 네트워크 재개, 백그라운드 작업."),
  "privacy":     ("추적기 제로.\n서버 제로.", "분석 없음. 오픈 소스. 엄격한 ATS, 어디서나 TLS 1.3."),
 },
 "pl": {
  "crypt-first": ("Każda chmura.\nZaszyfrowana.", "Natywne rclone crypt. Twoje klucze nigdy nie opuszczają iPhone’a."),
  "backends":    ("Ponad 80 usług.\nJedno miejsce.", LIST),
  "crypt-paths": ("Nazwy plików\nodszyfrowane w locie.", "Żadnego tekstu jawnego w tranzycie. AES-256 + NaCl secretbox."),
  "stream":      ("Strumieniuj wprost.\nBez pobierania.", "Zdjęcia, wideo, PDF — otwierane prosto z Plików."),
  "home":        ("Twoje centrum\ndowodzenia.", "Transfery, ulubione, sync zdjęć, prędkość. Na pierwszy rzut oka."),
  "wizard":      ("Konfiguracja\nz kreatorem.", "OAuth w dwóch dotknięciach. Import rclone.conf jednym gestem."),
  "photos":      ("Inteligentna\nkopia zdjęć.", "Adaptacyjny limit, wznawianie sieci, zadania w tle."),
  "privacy":     ("Zero trackerów.\nZero serwerów.", "Bez analityki. Open source. Ścisłe ATS, TLS 1.3 wszędzie."),
 },
 "zh": {
  "crypt-first": ("每一朵云。\n全程加密。", "原生 rclone crypt。密钥永不离开 iPhone。"),
  "backends":    ("80+ 服务。\n一处管理。", LIST),
  "crypt-paths": ("文件名即时\n解密。", "传输全程无明文。AES-256 + NaCl secretbox。"),
  "stream":      ("直接串流。\n无需下载。", "照片、视频、PDF — 从“文件”直接打开。"),
  "home":        ("你的\n控制中心。", "传输、收藏、照片同步、速度，一目了然。"),
  "wizard":      ("向导式\n配置。", "两次轻点完成 OAuth。一个手势导入 rclone.conf。"),
  "photos":      ("智能\n照片备份。", "自适应限速、断网续传、后台任务。"),
  "privacy":     ("零追踪。\n零服务器。", "无分析统计。开源。严格 ATS，全程 TLS 1.3。"),
 },
}

# lang -> which screenshot locale to use (fr uses fr UI, everyone else uses en UI)
def shot_locale(lang): return "fr" if lang == "fr" else "en"

DEVICES = {
    "iphone": dict(W=1320, H=2868, kicker="RCLONE GUI · iOS",
                   sw=1144, sx=88, sy=880, radius=60,
                   h_top=230, h_size=110, h_ls=-2, h_lh=1.02,
                   sub_size=38, sub_top=470, sub_mw=920, pill_top=130, decor_scale=1.0),
    "ipad":   dict(W=2064, H=2752, kicker="RCLONE GUI · iPad",
                   sw=1560, sx=252, sy=980, radius=44,
                   h_top=250, h_size=128, h_ls=-2.5, h_lh=1.0,
                   sub_size=44, sub_top=560, sub_mw=1300, pill_top=150, decor_scale=1.5),
}

def decor_svg(kind, accent, scale):
    s = scale
    if kind == "lock":
        return (f'<svg viewBox="0 0 200 200" style="position:absolute;right:{-40*s}px;top:{-40*s}px;'
                f'width:{360*s}px;height:{360*s}px;opacity:.08"><rect x="40" y="90" width="120" height="90" rx="20" fill="{accent}"/>'
                f'<path d="M65 90V60a35 35 0 0 1 70 0v30" fill="none" stroke="{accent}" stroke-width="22"/></svg>')
    if kind == "cloud":
        return (f'<svg viewBox="0 0 200 200" style="position:absolute;right:{-30*s}px;top:{-20*s}px;'
                f'width:{320*s}px;height:{320*s}px;opacity:.09"><path d="M55 145a30 30 0 0 1-4-59 42 42 0 0 1 82-5 30 30 0 0 1-3 64H55Z" fill="{accent}"/></svg>')
    if kind == "sparkle":
        star = "M50 10 L57 43 L90 50 L57 57 L50 90 L43 57 L10 50 L43 43 Z"
        return (f'<svg viewBox="0 0 100 100" style="position:absolute;right:{80*s}px;top:{80*s}px;width:{100*s}px;height:{100*s}px;opacity:.18"><path d="{star}" fill="{accent}"/></svg>'
                f'<svg viewBox="0 0 100 100" style="position:absolute;right:{260*s}px;top:{40*s}px;width:{60*s}px;height:{60*s}px;opacity:.14"><path d="{star}" fill="{accent}"/></svg>')
    return ""

LOCK_ICON = ('<svg width="26" height="26" viewBox="0 0 24 24" fill="none">'
             '<rect x="5" y="11" width="14" height="9" rx="2.2" fill="currentColor"/>'
             '<path d="M8 11V8a4 4 0 0 1 8 0v3" stroke="currentColor" stroke-width="2.4" fill="none"/></svg>')

def data_uri(path):
    with open(path, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()

def headline_html(text):
    return "<br>".join(html.escape(l) for l in text.split("\n"))

def build_html(device, lang, screen):
    sid, pal_name, decor, base = screen
    d = DEVICES[device]
    p = PALETTES[pal_name]
    accent = p["accent"]; dark = p["dark"]
    fg = "#fff" if dark else "#0B0820"
    sub_fg = "rgba(255,255,255,0.72)" if dark else "rgba(11,8,32,0.55)"
    pill_bg = "rgba(255,255,255,0.08)" if dark else "rgba(255,255,255,0.62)"
    head, sub = COPY[lang][sid]
    shot = os.path.join(SHOTS, device, shot_locale(lang), base + ".png")
    img = data_uri(shot)
    # screen image natural aspect (portrait) → scaled to width sw
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
*{{box-sizing:border-box;-webkit-font-smoothing:antialiased}}
html,body{{margin:0;padding:0}}
#ab{{width:{d['W']}px;height:{d['H']}px;position:relative;overflow:hidden;
  background:linear-gradient(180deg,{p['a']} 0%,{p['b']} 100%);
  font-family:-apple-system,'SF Pro Display','Helvetica Neue',system-ui,sans-serif;color:{fg}}}
.pill{{position:absolute;top:{d['pill_top']}px;left:0;right:0;display:flex;justify-content:center}}
.pill>span{{display:inline-flex;align-items:center;gap:12px;padding:14px 30px;border-radius:999px;
  background:{pill_bg};border:1px solid {accent}33;color:{accent};
  font-size:28px;font-weight:700;letter-spacing:.6px;backdrop-filter:blur(20px)}}
.head{{position:absolute;top:{d['h_top']}px;left:96px;right:96px;text-align:center}}
.head h1{{margin:0;font-size:{d['h_size']}px;font-weight:800;letter-spacing:{d['h_ls']}px;line-height:{d['h_lh']};color:{fg}}}
.head p{{margin:24px auto 0;font-size:{d['sub_size']}px;font-weight:500;letter-spacing:-.3px;line-height:1.25;
  color:{sub_fg};max-width:{d['sub_mw']}px}}
.shot{{position:absolute;left:{d['sx']}px;top:{d['sy']}px;width:{d['sw']}px;border-radius:{d['radius']}px;overflow:hidden;
  box-shadow:0 60px 120px {accent}55,0 24px 60px rgba(0,0,0,.18)}}
.shot img{{display:block;width:100%}}
</style></head><body><div id="ab">
{decor_svg(decor, accent, d['decor_scale'])}
<div class="pill"><span>{LOCK_ICON}{html.escape(d['kicker'])}</span></div>
<div class="head"><h1>{headline_html(head)}</h1><p>{html.escape(sub)}</p></div>
<div class="shot"><img src="{img}"/></div>
</div></body></html>"""

def render(device, langs):
    d = DEVICES[device]
    for lang in langs:
        outdir = os.path.join(OUT, device, lang)
        os.makedirs(outdir, exist_ok=True)
        for i, screen in enumerate(SCREENS, 1):
            sid = screen[0]
            htmlpath = f"/tmp/_ab_{device}_{lang}_{i}.html"
            with open(htmlpath, "w") as f:
                f.write(build_html(device, lang, screen))
            out = os.path.join(outdir, f"{i:02d}_{screen[3].split('_',1)[1]}.png")
            subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                            "--force-device-scale-factor=1", f"--window-size={d['W']},{d['H']}",
                            f"--screenshot={out}", f"file://{htmlpath}"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            os.remove(htmlpath)
            # Tag an explicit sRGB profile. Chrome emits an *untagged* PNG, which
            # App Store Connect can render as a solid black thumbnail; embedding
            # sRGB (no pixel change) makes the upload bulletproof.
            if os.path.exists(SRGB_PROFILE):
                subprocess.run(["sips", "-m", SRGB_PROFILE, out, "--out", out],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print(f"✓ {device} [{lang}] 8 frames")

if __name__ == "__main__":
    device = sys.argv[1] if len(sys.argv) > 1 else "iphone"
    langs = sys.argv[2].split(",") if len(sys.argv) > 2 else list(COPY.keys())
    render(device, langs)
