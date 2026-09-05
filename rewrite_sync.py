import re

with open('.github/workflows/sync-upstream.yml', 'r') as f:
    content = f.read()

# Replace the mpv checking logic
old_mpv_logic = r'''          # 3\. Ensure libmpv-android fork is up to date.*?# 5\. Fetch AAR & compute SHA256.*?echo "Using libmpv-android: \$MPV_LATEST_RELEASE \(\$MPV_SHA256\)"'''

new_mpv_logic = r'''          # 3. Ensure mpv-build fork is up to date
          echo "Checking mpv-build upstream..."
          gh auth setup-git
          git clone https://github.com/swmarks/mpv-build.git /tmp/mpv-build
          cd /tmp/mpv-build
          git remote add upstream https://github.com/edde746/mpv-build.git
          git fetch upstream
          
          BEHIND=$(git rev-list --count HEAD..upstream/main)
          REBUILD_MPV=false
          if [ "$BEHIND" -gt 0 ] || [ "$FORCE_REBUILD" = "true" ]; then
            echo "mpv-build fork is behind by $BEHIND commits, rebasing..."
            git config --global user.name "github-actions[bot]"
            git config --global user.email "github-actions[bot]@users.noreply.github.com"
            
            # Rebase but keep our custom patches
            git rebase upstream/main
            
            # The AC4 patch might need to be reapplied or it is already in our history. 
            # If rebase is clean, we just push it.
            git push origin main --force
            REBUILD_MPV=true
          else
            echo "mpv-build fork is up to date."
          fi
          
          MPV_SHA=$(git rev-parse HEAD)
          cd -

          if [ "$REBUILD_MPV" = "true" ]; then
            echo "Waiting for mpv-build publish to complete..."
            sleep 60
            while true; do
              RUN_STATUS=$(gh run list --repo swmarks/mpv-build --workflow "publish.yml" --limit 1 --json status,conclusion --jq '.[0]')
              STATUS=$(echo "$RUN_STATUS" | jq -r '.status')
              CONCLUSION=$(echo "$RUN_STATUS" | jq -r '.conclusion')
              if [ "$STATUS" = "completed" ]; then
                if [ "$CONCLUSION" = "success" ]; then
                  echo "mpv-build publish succeeded!"
                  break
                else
                  echo "mpv-build publish failed ($CONCLUSION)!"
                  exit 1
                fi
              fi
              echo "Build in progress... waiting 30s"
              sleep 30
            done
          fi
'''

content = re.sub(old_mpv_logic, new_mpv_logic, content, flags=re.DOTALL)

# Replace the output echoing
content = content.replace('echo "mpv_version=$MPV_LATEST_RELEASE" >> $GITHUB_OUTPUT\n          echo "mpv_sha256=$MPV_SHA256" >> $GITHUB_OUTPUT', 'echo "mpv_sha=$MPV_SHA" >> $GITHUB_OUTPUT')

# Replace the env mapping
content = content.replace('MPV_VERSION: ${{ steps.check_status.outputs.mpv_version }}\n          MPV_SHA256: ${{ steps.check_status.outputs.mpv_sha256 }}', 'MPV_SHA: ${{ steps.check_status.outputs.mpv_sha }}')

# Replace the patch execution
content = content.replace('./scripts/patch-ac4.sh "$MPV_VERSION" "$MPV_SHA256"', '''# Set native revision first (updates mpv-build.lock.json and Apple projects)
          ./scripts/set_native_revision.sh "$MPV_SHA" --repo https://github.com/swmarks/mpv-build
          
          # 5. Apply idempotent AC-4 patches
          ./scripts/patch-ac4.sh''')

with open('.github/workflows/sync-upstream.yml', 'w') as f:
    f.write(content)
