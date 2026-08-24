import re

with open('android/app/src/main/kotlin/com/edde746/plezy/exoplayer/ExoPlayerCore.kt', 'r') as f:
    text = f.read()

text = re.sub(
    r'\"codec\" to \(format\.codecs \?: when \(format\.sampleMimeType\) \{',
    r'"codec" to (when (format.sampleMimeType) {',
    text
)

text = re.sub(
    r'else -> format\.sampleMimeType\?\.substringAfterLast\(\'/\'\)',
    r'else -> format.codecs ?: format.sampleMimeType?.substringAfterLast(\'/\')',
    text
)

with open('android/app/src/main/kotlin/com/edde746/plezy/exoplayer/ExoPlayerCore.kt', 'w') as f:
    f.write(text)
print("Regex replaced ExoPlayerCore.kt")
