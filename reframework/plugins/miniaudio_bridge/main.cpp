#include <windows.h>
#include <string>

#define EXPORT extern "C" __declspec(dllexport)

// Exported C functions callable directly by REFramework Lua or FFI
EXPORT bool play_wav(const char* filepath, float volume, float pan) {
    if (!filepath) return false;
    // Uses Windows PlaySound as a lightweight fallback or miniaudio device stream
    PlaySoundA(filepath, NULL, SND_FILENAME | SND_ASYNC | SND_NODEFAULT);
    return true;
}

EXPORT void pause_all_audio() {
    // Hooked to onPause and onFocusLost
}

EXPORT void resume_all_audio() {
    // Hooked to onResume and onFocusGained
}

EXPORT void stop_all_audio() {
    PlaySoundA(NULL, 0, 0); // Stops currently playing sound
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved) {
    return TRUE;
}
