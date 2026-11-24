package com.chintunes.chintunes

import com.ryanheise.audioservice.AudioServiceActivity

// audio_service requires the host activity to extend AudioServiceActivity so the
// Flutter engine is shared with the background playback service.
class MainActivity : AudioServiceActivity()
