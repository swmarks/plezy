#!/bin/bash
set -e

echo "==> Applying AC-4 patches to Plezy codebase..."

# 1. CodecUtils AC-4 display format
python3 -c "
with open('lib/utils/codec_utils.dart', 'r') as f:
    text = f.read()

if \"'ac4' => 'AC4'\" not in text:
    text = text.replace(
        \"'ac3' || 'ac-3' => 'AC3',\",
        \"'ac3' || 'ac-3' => 'AC3',\n      'ac4' => 'AC4',\"
    )
    with open('lib/utils/codec_utils.dart', 'w') as f:
        f.write(text)
    print('  [✓] Patched lib/utils/codec_utils.dart')
else:
    print('  [-] lib/utils/codec_utils.dart already patched')
"


# 1b. CodecUtils: map tx3g MIME type to MOV display label and recognize as text subtitle
python3 -c "
with open('lib/utils/codec_utils.dart', 'r') as f:
    text = f.read()

changed = False

# formatSubtitleCodec: recognize the raw MIME as MOV
if 'APPLICATION/X-QUICKTIME-TX3G' not in text:
    text = text.replace(
        \"'MOV_TEXT' => 'MOV',\",
        \"'MOV_TEXT' || 'APPLICATION/X-QUICKTIME-TX3G' => 'MOV',\n      'APPLICATION/X-MP4-CEA-608' => 'CC',\"
    )
    changed = True

# isTextSubtitleCodec: recognize the raw MIME as text subtitle
if 'application/x-quicktime-tx3g' not in text:
    text = text.replace(
        \"'srt' || 'subrip' || 'ass' || 'ssa' || 'webvtt' || 'vtt' || 'mov_text' => true,\",
        \"'srt' || 'subrip' || 'ass' || 'ssa' || 'webvtt' || 'vtt' || 'mov_text' || 'application/x-quicktime-tx3g' => true,\"
    )
    changed = True

if changed:
    with open('lib/utils/codec_utils.dart', 'w') as f:
        f.write(text)
    print('  [✓] Patched codec_utils.dart for tx3g MIME display')
else:
    print('  [-] codec_utils.dart tx3g MIME already patched')
"

# 2. Plex Client HLS Transcode Targets
python3 -c "
with open('lib/services/plex_client.dart', 'r') as f:
    text = f.read()

if '%2Cac4' not in text:
    text = text.replace(
        '&audioCodec=aac%2Cac3%2Ceac3%2Cmp3)',
        '&audioCodec=aac%2Cac3%2Ceac3%2Cmp3%2Cac4)'
    )
    with open('lib/services/plex_client.dart', 'w') as f:
        f.write(text)
    print('  [✓] Patched lib/services/plex_client.dart')
else:
    print('  [-] lib/services/plex_client.dart already patched')
"

# 3. Jellyfin Client Transcode Profiles — add ac4 to the transcode AudioCodec lists
#    (DirectPlayProfiles omits AudioCodec entirely = "any codec", so AC-4 direct play
#    already works. But the *transcode* targets still enumerate codecs explicitly.)
python3 -c "
with open('lib/services/jellyfin_client/parts/playback.dart', 'r') as f:
    text = f.read()

changed = False

# fMP4 transcode target
if \"'AudioCodec': 'aac,mp3,ac3,eac3,flac,opus,dts,truehd',\" in text:
    text = text.replace(
        \"'AudioCodec': 'aac,mp3,ac3,eac3,flac,opus,dts,truehd',\",
        \"'AudioCodec': 'aac,mp3,ac3,eac3,flac,opus,dts,truehd,ac4',\"
    )
    changed = True

# TS transcode target
if \"'AudioCodec': 'aac,mp3,ac3,eac3,opus,dts',\" in text:
    text = text.replace(
        \"'AudioCodec': 'aac,mp3,ac3,eac3,opus,dts',\",
        \"'AudioCodec': 'aac,mp3,ac3,eac3,opus,dts,ac4',\"
    )
    changed = True

if changed:
    with open('lib/services/jellyfin_client/parts/playback.dart', 'w') as f:
        f.write(text)
    print('  [✓] Patched lib/services/jellyfin_client/parts/playback.dart')
else:
    print('  [-] lib/services/jellyfin_client/parts/playback.dart already patched')
"

# 4. ExoPlayer Audio Fallback to MPV & Subtitle Codec Reporting
python3 -c "
with open('android/app/src/main/kotlin/com/edde746/plezy/exoplayer/ExoPlayerCore.kt', 'r') as f:
    text = f.read()

changed = False

# 4a. Add audio fallback in requestFallbackForUnsupportedTracks.
#     Upstream 2.22.0 uses an early return for video instead of val videoFailed:
#       if (!hasAnyVideoGroup || hasSelectedVideo) return
#     We inject an audio check right before the video early-return line.
if 'hasSupportedAudio' not in text:
    old_video_check = '''    if (!hasAnyVideoGroup || hasSelectedVideo) return

    if (retryWithDvConversion(\"video track not selected\")) return'''

    new_video_check = '''    // AC-4: also fall back when audio tracks exist but none are supported
    val hasAnyAudioGroup = tracks.groups.any { it.type == C.TRACK_TYPE_AUDIO }
    val hasSupportedAudio = tracks.groups.any { it.type == C.TRACK_TYPE_AUDIO && (it.isSelected || it.isSupported) }
    val audioFailed = hasAnyAudioGroup && !hasSupportedAudio

    if (audioFailed) {
      emitLog(\"warn\", \"fallback\", \"Audio track present but not supported (unsupported codec)\")
      requestFormatFallback(
        mediaGeneration = mediaGeneration,
        uri = uri,
        positionMs = effectivePosition,
        playWhenReady = exoPlayer?.playWhenReady ?: true,
        errorMessage = \"Audio track present but no decoder available\"
      )
      return
    }

    if (!hasAnyVideoGroup || hasSelectedVideo) return

    if (retryWithDvConversion(\"video track not selected\")) return'''

    if old_video_check in text:
        text = text.replace(old_video_check, new_video_check)
        changed = True
    else:
        print('  [!] Could not find video check anchor in requestFallbackForUnsupportedTracks')

# 4b. Subtitle codec mapping — replace bare format.codecs with when(sampleMimeType) block
old_sub_codec = '\"codec\" to format.codecs,'
new_sub_codec = '''\"codec\" to (when (format.sampleMimeType) {
          \"application/x-quicktime-tx3g\", \"application/x-mp4-cea-608\" -> \"mov_text\"
          \"application/x-subrip\" -> \"subrip\"
          \"text/x-ssa\" -> \"ass\"
          \"text/vtt\" -> \"vtt\"
          \"application/pgs\" -> \"pgs\"
          \"application/vobsub\" -> \"vobsub\"
          else -> format.codecs ?: format.sampleMimeType?.substringAfterLast('/')
        }),'''
if old_sub_codec in text:
    text = text.replace(old_sub_codec, new_sub_codec)
    changed = True

with open('android/app/src/main/kotlin/com/edde746/plezy/exoplayer/ExoPlayerCore.kt', 'w') as f:
    f.write(text)
if changed:
    print('  [✓] Patched android/app/src/main/kotlin/com/edde746/plezy/exoplayer/ExoPlayerCore.kt')
else:
    print('  [-] ExoPlayerCore.kt already patched')
"


# 6. Update unit test expectations in plex_playback_data_request_test.dart
if [ -f "test/services/plex_playback_data_request_test.dart" ]; then
    python3 -c "
with open('test/services/plex_playback_data_request_test.dart', 'r') as f:
    text = f.read()

if \"'&audioCodec=aac%2Cac3%2Ceac3%2Cmp3)',\" in text:
    text = text.replace(
        \"'&audioCodec=aac%2Cac3%2Ceac3%2Cmp3)',\",
        \"'&audioCodec=aac%2Cac3%2Ceac3%2Cmp3%2Cac4)',\"
    )
    with open('test/services/plex_playback_data_request_test.dart', 'w') as f:
        f.write(text)
    print('  [✓] Updated test expectations in test/services/plex_playback_data_request_test.dart')
else:
    print('  [-] test/services/plex_playback_data_request_test.dart already updated')
"
fi

# 7. Enable AC-4 in Media3 FfmpegLibrary.java
if [ -f "android/app/src/main/java/androidx/media3/decoder/ffmpeg/FfmpegLibrary.java" ]; then
    python3 -c "
with open('android/app/src/main/java/androidx/media3/decoder/ffmpeg/FfmpegLibrary.java', 'r') as f:
    text = f.read()

if 'case MimeTypes.AUDIO_AC4:' not in text:
    text = text.replace(
        'case MimeTypes.AUDIO_E_AC3_JOC:\n        return \"eac3\";',
        'case MimeTypes.AUDIO_E_AC3_JOC:\n        return \"eac3\";\n      case MimeTypes.AUDIO_AC4:\n        return \"ac4\";'
    )
    with open('android/app/src/main/java/androidx/media3/decoder/ffmpeg/FfmpegLibrary.java', 'w') as f:
        f.write(text)
    print('  [✓] Enabled AUDIO_AC4 in FfmpegLibrary.java')
else:
    print('  [-] FfmpegLibrary.java already has AUDIO_AC4')
"
fi

# 8. Ensure valid hwdec value for Android in video_player_screen.dart
if [ -f "lib/screens/video_player_screen.dart" ]; then
    python3 -c "
with open('lib/screens/video_player_screen.dart', 'r') as f:
    text = f.read()

changed = False

# Upstream 2.22.0 returns 'mediacodec,mediacodec-copy'
if \"return 'mediacodec,mediacodec-copy';\" in text:
    text = text.replace(\"return 'mediacodec,mediacodec-copy';\", \"return 'auto-safe';\")
    changed = True
# Earlier versions returned 'mediacodec,auto'
elif \"return 'mediacodec,auto';\" in text:
    text = text.replace(\"return 'mediacodec,auto';\", \"return 'auto-safe';\")
    changed = True

if changed:
    with open('lib/screens/video_player_screen.dart', 'w') as f:
        f.write(text)
    print('  [✓] Fixed hwdec in lib/screens/video_player_screen.dart')
else:
    print('  [-] lib/screens/video_player_screen.dart already using valid hwdec')
"
fi

# 9. Configure MpvPlayerCore initialize options for hardware decoding
if [ -f "android/app/src/main/kotlin/com/edde746/plezy/mpv/MpvPlayerCore.kt" ]; then
    python3 -c "
with open('android/app/src/main/kotlin/com/edde746/plezy/mpv/MpvPlayerCore.kt', 'r') as f:
    text = f.read()

if 'setOption(\"hwdec\", \"auto-safe\")' not in text:
    # Try the 2.22.0 anchor: opengl-es is still present
    if 'setOption(\"opengl-es\", \"yes\")' in text:
        text = text.replace(
            'setOption(\"opengl-es\", \"yes\")',
            'setOption(\"opengl-es\", \"yes\")\n              setOption(\"hwdec\", \"auto-safe\")\n              setOption(\"hwdec-codecs\", \"all\")'
        )
    # Fallback: try gpu-context anchor
    elif 'setOption(\"gpu-context\", \"android\")' in text:
        text = text.replace(
            'setOption(\"gpu-context\", \"android\")',
            'setOption(\"gpu-context\", \"android\")\n              setOption(\"hwdec\", \"auto-safe\")\n              setOption(\"hwdec-codecs\", \"all\")'
        )
    with open('android/app/src/main/kotlin/com/edde746/plezy/mpv/MpvPlayerCore.kt', 'w') as f:
        f.write(text)
    print('  [✓] Configured hwdec options in MpvPlayerCore.kt')
else:
    print('  [-] MpvPlayerCore.kt already has hwdec options')
"
fi

# 10. Enable AC-4 audio and mov_text subtitle MIME in FFmpeg demuxer JNI
#     (This file was removed in Plezy 2.18.0+; the check is retained for older versions)
if [ -f "android/app/src/main/cpp/media3_ffmpeg_demuxer/ffmpeg_demuxer_jni.cc" ]; then
    python3 -c "
import re
with open('android/app/src/main/cpp/media3_ffmpeg_demuxer/ffmpeg_demuxer_jni.cc', 'r') as f:
    text = f.read()

if 'case AV_CODEC_ID_AC4:' not in text:
    text = text.replace(
        'case AV_CODEC_ID_TRUEHD:\n      return \"audio/true-hd\";',
        'case AV_CODEC_ID_TRUEHD:\n      return \"audio/true-hd\";\n    case AV_CODEC_ID_AC4:\n      return \"audio/ac4\";'
    )

if 'case AV_CODEC_ID_MOV_TEXT:' not in text:
    text = re.sub(
        r'(return \"application/vobsub\";)',
        r'\1\n    case AV_CODEC_ID_MOV_TEXT:\n      return \"application/x-quicktime-tx3g\";',
        text
    )

with open('android/app/src/main/cpp/media3_ffmpeg_demuxer/ffmpeg_demuxer_jni.cc', 'w') as f:
    f.write(text)
print('  [✓] Enabled AV_CODEC_ID_AC4 and AV_CODEC_ID_MOV_TEXT in ffmpeg_demuxer_jni.cc')
"
fi

# 11. Fix FfmpegAudioRenderer sink support for streams with uninitialized channelCount or sampleRate
if [ -f "android/app/src/main/java/androidx/media3/decoder/ffmpeg/FfmpegAudioRenderer.java" ]; then
    python3 -c "
with open('android/app/src/main/java/androidx/media3/decoder/ffmpeg/FfmpegAudioRenderer.java', 'r') as f:
    text = f.read()

old_sink_method = '''  private boolean sinkSupportsFormat(Format inputFormat, @C.PcmEncoding int pcmEncoding) {
    return sinkSupportsFormat(
        Util.getPcmFormat(pcmEncoding, inputFormat.channelCount, inputFormat.sampleRate));
  }'''

new_sink_method = '''  private boolean sinkSupportsFormat(Format inputFormat, @C.PcmEncoding int pcmEncoding) {
    int channelCount = inputFormat.channelCount != Format.NO_VALUE ? inputFormat.channelCount : 2;
    int sampleRate = inputFormat.sampleRate != Format.NO_VALUE ? inputFormat.sampleRate : 48000;
    return sinkSupportsFormat(
        Util.getPcmFormat(pcmEncoding, channelCount, sampleRate));
  }'''

if old_sink_method in text:
    text = text.replace(old_sink_method, new_sink_method)

old_float_method = '''  private boolean shouldOutputFloat(Format inputFormat) {
    if (!sinkSupportsFormat(inputFormat, C.ENCODING_PCM_16BIT)) {
      return true;
    }

    @SinkFormatSupport
    int formatSupport =
        getSinkFormatSupport(
            Util.getPcmFormat(
                C.ENCODING_PCM_FLOAT, inputFormat.channelCount, inputFormat.sampleRate));'''

new_float_method = '''  private boolean shouldOutputFloat(Format inputFormat) {
    if (!sinkSupportsFormat(inputFormat, C.ENCODING_PCM_16BIT)) {
      return true;
    }

    int channelCount = inputFormat.channelCount != Format.NO_VALUE ? inputFormat.channelCount : 2;
    int sampleRate = inputFormat.sampleRate != Format.NO_VALUE ? inputFormat.sampleRate : 48000;
    @SinkFormatSupport
    int formatSupport =
        getSinkFormatSupport(
            Util.getPcmFormat(
                C.ENCODING_PCM_FLOAT, channelCount, sampleRate));'''

if old_float_method in text:
    text = text.replace(old_float_method, new_float_method)

with open('android/app/src/main/java/androidx/media3/decoder/ffmpeg/FfmpegAudioRenderer.java', 'w') as f:
    f.write(text)
print('  [✓] Configured channel/rate fallback in FfmpegAudioRenderer.java')
"
fi

# 12. Recreate AC-4 decoder context on seek (like TrueHD)
if [ -f "android/app/src/main/cpp/media3_ffmpeg_decoder/ffmpeg_jni.cc" ]; then
    python3 -c "
with open('android/app/src/main/cpp/media3_ffmpeg_decoder/ffmpeg_jni.cc', 'r') as f:
    text = f.read()

if 'codecId == AV_CODEC_ID_AC4' not in text:
    text = text.replace(
        'if (codecId == AV_CODEC_ID_TRUEHD) {',
        'if (codecId == AV_CODEC_ID_TRUEHD || codecId == AV_CODEC_ID_AC4) {'
    )
    with open('android/app/src/main/cpp/media3_ffmpeg_decoder/ffmpeg_jni.cc', 'w') as f:
        f.write(text)
    print('  [✓] Added AC-4 decoder context recreation on seek in ffmpeg_jni.cc')
else:
    print('  [-] ffmpeg_jni.cc already has AC-4 context recreation')
"
fi




echo "==> AC-4 patch application complete."
