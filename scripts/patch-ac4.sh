#!/bin/bash
set -e

MPV_VERSION="$1"
MPV_SHA256="$2"

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

# 3. Jellyfin Client Direct Play Profiles
python3 -c "
with open('lib/services/jellyfin_client/parts/playback.dart', 'r') as f:
    text = f.read()

changed = False
if \"'AudioCodec': 'aac,mp3,ac3,eac3,flac,opus',\" in text:
    text = text.replace(
        \"'AudioCodec': 'aac,mp3,ac3,eac3,flac,opus',\",
        \"'AudioCodec': 'aac,mp3,ac3,eac3,flac,opus,ac4',\"
    )
    changed = True

if \"'AudioCodec': 'aac,mp3,mp2,ac3,eac3,flac,opus,vorbis,dts',\" in text:
    text = text.replace(
        \"'AudioCodec': 'aac,mp3,mp2,ac3,eac3,flac,opus,vorbis,dts',\",
        \"'AudioCodec': 'aac,mp3,mp2,ac3,eac3,flac,opus,vorbis,dts,ac4',\"
    )
    changed = True

if changed:
    with open('lib/services/jellyfin_client/parts/playback.dart', 'w') as f:
        f.write(text)
    print('  [✓] Patched lib/services/jellyfin_client/parts/playback.dart')
else:
    print('  [-] lib/services/jellyfin_client/parts/playback.dart already patched')
"

# 4. ExoPlayer Audio Fallback to MPV (Robust to transient track evaluation) & Subtitle Codec Reporting
python3 -c "
with open('android/app/src/main/kotlin/com/edde746/plezy/exoplayer/ExoPlayerCore.kt', 'r') as f:
    text = f.read()

if 'val hasSupportedAudio' not in text:
    if 'val hasAnyAudioGroup' in text:
        old_block = '''    val hasAnyVideoGroup = tracks.groups.any { it.type == C.TRACK_TYPE_VIDEO }
    val hasSelectedVideo = tracks.groups.any { it.type == C.TRACK_TYPE_VIDEO && it.isSelected }
    val videoFailed = hasAnyVideoGroup && !hasSelectedVideo

    val hasAnyAudioGroup = tracks.groups.any { it.type == C.TRACK_TYPE_AUDIO }
    val hasSelectedAudio = tracks.groups.any { it.type == C.TRACK_TYPE_AUDIO && it.isSelected }
    val audioFailed = hasAnyAudioGroup && !hasSelectedAudio'''
    else:
        old_block = '''    val hasAnyVideoGroup = tracks.groups.any { it.type == C.TRACK_TYPE_VIDEO }
    val hasSelectedVideo = tracks.groups.any { it.type == C.TRACK_TYPE_VIDEO && it.isSelected }
    val videoFailed = hasAnyVideoGroup && !hasSelectedVideo'''

    new_block = '''    val hasAnyVideoGroup = tracks.groups.any { it.type == C.TRACK_TYPE_VIDEO }
    val hasSelectedVideo = tracks.groups.any { it.type == C.TRACK_TYPE_VIDEO && it.isSelected }
    val videoFailed = hasAnyVideoGroup && !hasSelectedVideo

    val hasAnyAudioGroup = tracks.groups.any { it.type == C.TRACK_TYPE_AUDIO }
    val hasSupportedAudio = tracks.groups.any { it.type == C.TRACK_TYPE_AUDIO && (it.isSelected || it.isSupported) }
    val audioFailed = hasAnyAudioGroup && !hasSupportedAudio'''

    text = text.replace(old_block, new_block)

if 'val hasAudioTrack = player.currentTracks.groups.any' in text:
    old_watchdog = '''        val hasAudioTrack = player.currentTracks.groups.any {
          it.type == C.TRACK_TYPE_AUDIO && it.isSelected
        }'''
    new_watchdog = '''        val hasAudioTrack = player.currentTracks.groups.any {
          it.type == C.TRACK_TYPE_AUDIO && (it.isSelected || it.isSupported)
        }'''
    text = text.replace(old_watchdog, new_watchdog)

old_sub_codec = '\"codec\" to format.codecs,'
new_sub_codec = '''\"codec\" to (format.codecs ?: when (format.sampleMimeType) {
          \"application/x-quicktime-tx3g\", \"application/x-mp4-cea-608\" -> \"mov_text\"
          \"application/x-subrip\" -> \"subrip\"
          \"text/x-ssa\" -> \"ass\"
          \"text/vtt\" -> \"vtt\"
          \"application/pgs\" -> \"pgs\"
          \"application/vobsub\" -> \"vobsub\"
          else -> format.sampleMimeType?.substringAfterLast('/')
        }),'''

if old_sub_codec in text:
    text = text.replace(old_sub_codec, new_sub_codec)

with open('android/app/src/main/kotlin/com/edde746/plezy/exoplayer/ExoPlayerCore.kt', 'w') as f:
    f.write(text)
print('  [✓] Patched android/app/src/main/kotlin/com/edde746/plezy/exoplayer/ExoPlayerCore.kt')
"

# 5. Update build.gradle.kts with custom libmpv-android
if [ -n "$MPV_VERSION" ] && [ -n "$MPV_SHA256" ]; then
    python3 -c "
import re
with open('android/app/build.gradle.kts', 'r') as f:
    text = f.read()

text = re.sub(r'val mpvVersion = \".*?\"', f'val mpvVersion = \"$MPV_VERSION\"', text)
text = re.sub(r'val mpvSha256 = \".*?\"', f'val mpvSha256 = \"$MPV_SHA256\"', text)
text = re.sub(r'https://github\.com/edde746/libmpv-android', 'https://github.com/swmarks/libmpv-android', text)

with open('android/app/build.gradle.kts', 'w') as f:
    f.write(text)
print('  [✓] Configured libmpv-android $MPV_VERSION ($MPV_SHA256) in build.gradle.kts')
"
fi

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

if \"return 'mediacodec,mediacodec-copy';\" in text:
    text = text.replace(\"return 'mediacodec,mediacodec-copy';\", \"return 'auto-safe';\")
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
    text = text.replace(
        'setOption(\"opengl-es\", \"yes\")',
        'setOption(\"opengl-es\", \"yes\")\n              setOption(\"hwdec\", \"auto-safe\")\n              setOption(\"hwdec-codecs\", \"all\")'
    )
    with open('android/app/src/main/kotlin/com/edde746/plezy/mpv/MpvPlayerCore.kt', 'w') as f:
        f.write(text)
    print('  [✓] Configured hwdec options in MpvPlayerCore.kt')
else:
    print('  [-] MpvPlayerCore.kt already has hwdec options')
"
fi

# 10. Enable AC-4 audio and mov_text subtitle MIME in FFmpeg demuxer JNI (Plezy 2.17.0+)
if [ -f "android/app/src/main/cpp/media3_ffmpeg_demuxer/ffmpeg_demuxer_jni.cc" ]; then
    python3 -c "
with open('android/app/src/main/cpp/media3_ffmpeg_demuxer/ffmpeg_demuxer_jni.cc', 'r') as f:
    text = f.read()

if 'case AV_CODEC_ID_AC4:' not in text:
    text = text.replace(
        'case AV_CODEC_ID_EAC3:\n      return \"audio/eac3\";',
        'case AV_CODEC_ID_EAC3:\n      return \"audio/eac3\";\n    case AV_CODEC_ID_AC4:\n      return \"audio/ac4\";'
    )

if 'case AV_CODEC_ID_MOV_TEXT:' not in text:
    text = text.replace(
        'case AV_CODEC_ID_DVD_SUBTITLE:\n      return \"application/vobsub\";',
        'case AV_CODEC_ID_DVD_SUBTITLE:\n      return \"application/vobsub\";\n    case AV_CODEC_ID_MOV_TEXT:\n      return \"application/x-quicktime-tx3g\";'
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
