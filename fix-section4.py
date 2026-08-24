import re

with open('scripts/patch-ac4.sh', 'r') as f:
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

with open('scripts/patch-ac4.sh', 'w') as f:
    f.write(text)
print("Regex replaced patch-ac4.sh")
