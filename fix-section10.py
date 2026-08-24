with open('scripts/patch-ac4.sh', 'r') as f:
    text = f.read()

start_idx = text.find('# 10. Enable AC-4 audio and mov_text subtitle MIME')
end_idx = text.find('# 11.', start_idx)

new_section = """# 10. Enable AC-4 audio and mov_text subtitle MIME in FFmpeg demuxer JNI (Plezy 2.17.0+)
if [ -f "android/app/src/main/cpp/media3_ffmpeg_demuxer/ffmpeg_demuxer_jni.cc" ]; then
    python3 -c "
import re
with open('android/app/src/main/cpp/media3_ffmpeg_demuxer/ffmpeg_demuxer_jni.cc', 'r') as f:
    text = f.read()

if 'case AV_CODEC_ID_TRUEHD:\\n      return \\\"audio/true-hd\\\";\\n    case AV_CODEC_ID_AC4:' not in text:
    text = text.replace(
        'case AV_CODEC_ID_TRUEHD:\\n      return \\\"audio/true-hd\\\";',
        'case AV_CODEC_ID_TRUEHD:\\n      return \\\"audio/true-hd\\\";\\n    case AV_CODEC_ID_AC4:\\n      return \\\"audio/ac4\\\";'
    )

if 'case AV_CODEC_ID_MOV_TEXT:' not in text:
    text = re.sub(
        r'(return \\\"application/vobsub\\\";)',
        r'\\1\\n    case AV_CODEC_ID_MOV_TEXT:\\n      return \\\"application/x-quicktime-tx3g\\\";',
        text
    )

with open('android/app/src/main/cpp/media3_ffmpeg_demuxer/ffmpeg_demuxer_jni.cc', 'w') as f:
    f.write(text)
print('  [✓] Enabled AV_CODEC_ID_AC4 and AV_CODEC_ID_MOV_TEXT in ffmpeg_demuxer_jni.cc')
"
fi

"""

text = text[:start_idx] + new_section + text[end_idx:]

with open('scripts/patch-ac4.sh', 'w') as f:
    f.write(text)
print('Fixed patch-ac4.sh')
