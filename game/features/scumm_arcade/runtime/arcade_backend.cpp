// SPDX-License-Identifier: GPL-3.0-or-later
// Deterministic ScummVM backend. This replaces the null platform at build time.
// All peers run the SAME wasm, including desktop clients (in a local Node worker).
#define FORBIDDEN_SYMBOL_ALLOW_ALL
#include <emscripten.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "common/scummsys.h"
#include "common/events.h"
#include "common/queue.h"
#include "backends/modular-backend.h"
#include "backends/graphics/null/null-graphics.h"
#include "backends/mixer/null/null-mixer.h"
#include "backends/mutex/null/null-mutex.h"
#include "backends/fs/posix/posix-fs-factory.h"
#include "backends/saves/default/default-saves.h"
#include "backends/timer/default/default-timer.h"
#include "backends/events/default/default-events.h"
#include "graphics/surface.h"
#include "base/main.h"

static uint32 clockMs = 0;
static Common::Queue<Common::Event> inputs;
static byte rgba[320 * 200 * 4];
static int16 pcm[441 * 2];
static int mouseX = 160, mouseY = 100;

// Resolving this promise is the ONLY way game time advances. Wall time, rendering
// rate, network jitter, audio devices and browser visibility cannot advance it.
EM_ASYNC_JS(void, waitForTick, (), {
    await new Promise(resolve => {
        Module.arcadeResume = resolve;
        if (Module.arcadeOnYield) Module.arcadeOnYield();
    });
});
EM_JS(void, publishFrame, (const byte *pixels, const int16 *audio), {
    Module.arcadePixels = HEAPU8.slice(pixels, pixels + 320 * 200 * 4);
    Module.arcadePCM = HEAPU8.slice(audio, audio + 441 * 4);
});

class ArcadeGraphics : public NullGraphicsManager {
    Graphics::Surface screen;
    byte palette[768] = {};
    byte cursor[4096] = {};
    uint cw = 0, ch = 0, transparent = 255;
    int hx = 0, hy = 0;
    bool cursorVisible = false;
public:
    ~ArcadeGraphics() override { screen.free(); }
    void initSize(uint w, uint h, const Graphics::PixelFormat *fmt = nullptr) override {
        if (w != 320 || h != 200 || (fmt && fmt->bytesPerPixel != 1))
            error("Arcade backend only supports the Monkey Island EGA demo (320x200 indexed)");
        NullGraphicsManager::initSize(w, h, fmt);
        screen.free();
        screen.create(w, h, Graphics::PixelFormat::createFormatCLUT8());
        fillScreen(0);
    }
    void setPalette(const byte *p, uint first, uint count) override {
        if (first + count <= 256) memcpy(palette + first * 3, p, count * 3);
    }
    void grabPalette(byte *p, uint first, uint count) const override {
        if (first + count <= 256) memcpy(p, palette + first * 3, count * 3);
    }
    void copyRectToScreen(const void *p, int pitch, int x, int y, int w, int h) override {
        if (!screen.getPixels() || x < 0 || y < 0 || x + w > screen.w || y + h > screen.h)
            return;
        for (int row = 0; row < h; ++row)
            memcpy(screen.getBasePtr(x, y + row), (const byte *)p + row * pitch, w);
    }
    Graphics::Surface *lockScreen() override { return &screen; }
    void fillScreen(uint32 color) override {
        if (screen.getPixels()) screen.fillRect(Common::Rect(screen.w, screen.h), color);
    }
    void fillScreen(const Common::Rect &r, uint32 color) override { screen.fillRect(r, color); }
    bool showMouse(bool visible) override {
        bool previous = cursorVisible;
        cursorVisible = visible;
        return previous;
    }
    void warpMouse(int x, int y) override { mouseX = x; mouseY = y; }
    void setMouseCursor(const void *p, uint w, uint h, int hotspotX, int hotspotY,
                        uint32 keycolor, bool dontScale = false,
                        const Graphics::PixelFormat *fmt = nullptr,
                        const byte *mask = nullptr) override {
        if (w * h > sizeof(cursor) || (fmt && fmt->bytesPerPixel != 1)) return;
        memcpy(cursor, p, w * h);
        cw = w; ch = h; hx = hotspotX; hy = hotspotY; transparent = keycolor;
    }
    void render() {
        if (!screen.getPixels()) return;
        for (int y = 0; y < 200; ++y) for (int x = 0; x < 320; ++x) {
            uint c = *(const byte *)screen.getBasePtr(x, y);
            int cx = x - mouseX + hx, cy = y - mouseY + hy;
            if (cursorVisible && cx >= 0 && cy >= 0 && cx < (int)cw && cy < (int)ch) {
                uint cc = cursor[cy * cw + cx];
                if (cc != transparent) c = cc;
            }
            int offset = (y * 320 + x) * 4;
            memcpy(rgba + offset, palette + c * 3, 3);
            rgba[offset + 3] = 255;
        }
    }
};

class ArcadeMixer : public NullMixerManager {
public:
    void tick() { _mixer->mixCallback((byte *)pcm, sizeof(pcm)); }
};

class ArcadeSystem : public ModularMixerBackend, public ModularGraphicsBackend,
                     public Common::EventSource {
public:
    ArcadeSystem() { _fsFactory = new POSIXFilesystemFactory(); }
    void initBackend() override {
        _timerManager = new DefaultTimerManager();
        _eventManager = new DefaultEventManager(this);
        _savefileManager = new DefaultSaveFileManager("/saves");
        _graphicsManager = new ArcadeGraphics();
        _mixerManager = new ArcadeMixer();
        _mixerManager->init();
        BaseBackend::initBackend();
    }
    bool pollEvent(Common::Event &event) override {
        if (inputs.empty()) return false;
        event = inputs.pop();
        return true;
    }
    Common::MutexInternal *createMutex() override { return new NullMutexInternal(); }
    uint32 getMillis(bool skipRecord = false) override { return clockMs; }
    void delayMillis(uint duration) override {
        uint32 until = clockMs + duration;
        while (clockMs < until) {
            ((ArcadeGraphics *)_graphicsManager)->render();
            publishFrame(rgba, pcm);
            waitForTick();
            clockMs += 20;
            ((DefaultTimerManager *)_timerManager)->handler();
            ((ArcadeMixer *)_mixerManager)->tick();
        }
    }
    void getTimeAndDate(TimeDate &td, bool skipRecord = false) const override {
        memset(&td, 0, sizeof(td));
        td.tm_year = 90; td.tm_mon = 9; td.tm_mday = 1; td.tm_wday = 1;
    }
    void quit() override { emscripten_force_exit(0); }
    void logMessage(LogMessageType::Type type, const char *message) override {
        fprintf(stderr, "%s\n", message);
    }
    void addSysArchivesToSearchSet(Common::SearchSet &, int) override {}
};

extern "C" EMSCRIPTEN_KEEPALIVE void arcade_input(int kind, int x, int y, int key) {
    Common::Event event;
    event.mouse.x = x; event.mouse.y = y;
    switch (kind) {
    case 0: event.type = Common::EVENT_MOUSEMOVE; mouseX = x; mouseY = y; break;
    case 1: event.type = Common::EVENT_LBUTTONDOWN; break;
    case 2: event.type = Common::EVENT_LBUTTONUP; break;
    case 3: event.type = Common::EVENT_RBUTTONDOWN; break;
    case 4: event.type = Common::EVENT_RBUTTONUP; break;
    case 5: event.type = Common::EVENT_KEYDOWN; event.kbd.keycode = (Common::KeyCode)key;
            event.kbd.ascii = key; break;
    case 6: event.type = Common::EVENT_KEYUP; event.kbd.keycode = (Common::KeyCode)key;
            event.kbd.ascii = key; break;
    default: return;
    }
    inputs.push(event);
}
int main(int argc, char **argv) {
    g_system = new ArcadeSystem();
    return scummvm_main(argc, argv);
}
