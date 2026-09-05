import re

with open('.github/workflows/build-android.yml', 'r') as f:
    content = f.read()

old_patch = r'''      - name: Apply AC-4 patches
        env:
          GH_TOKEN: \$\{\{ secrets.GITHUB_TOKEN \}\}
        run: \|
          chmod \+x scripts/patch-ac4.sh
          MPV_VERSION=\$\(gh api repos/swmarks/libmpv-android/releases/latest --jq '\.tag_name' 2>/dev/null \|\| echo ""\)
          if \[ -z "\$MPV_VERSION" \]; then
            echo "Error: No libmpv-android release found"
            exit 1
          fi
          gh release download "\$MPV_VERSION" --repo swmarks/libmpv-android --pattern "libmpv-release\.aar" --output /tmp/libmpv-release\.aar --clobber
          MPV_SHA256=\$\(sha256sum /tmp/libmpv-release\.aar \| awk '\{print \$1\}'\)
          bash scripts/patch-ac4.sh "\$MPV_VERSION" "\$MPV_SHA256"'''

new_patch = r'''      - name: Apply AC-4 patches
        run: |
          chmod +x scripts/patch-ac4.sh
          bash scripts/patch-ac4.sh'''

content = re.sub(old_patch, new_patch, content)

with open('.github/workflows/build-android.yml', 'w') as f:
    f.write(content)
