#!/usr/bin/env bash

set -euo pipefail

if [[ -z "${SLACK_TOKEN-}" ]]; then
    read -r SLACK_TOKEN
fi
SLACK_HOOK_URL="https://hooks.slack.com/services/${SLACK_TOKEN}"

: "${GITHUB_SERVER_URL:=https://github.com}"
: "${GITHUB_API_URL:=https://api.github.com}"
: "${GITHUB_SHA:=$(git rev-parse HEAD)}"
: "${PICTURE_BASE_URL:=https://github.com/juliaogris/pic/raw/master/github}"

if [[ -z "${GITHUB_REPOSITORY-}" ]]; then
    REPO_URL=$(git remote get-url origin)
    GITHUB_REPOSITORY="${REPO_URL#${GITHUB_SERVER_URL}/}"
else
    REPO_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}"
fi
REPO=${GITHUB_REPOSITORY#*/}

: "${BUILD_URL:=${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions${GITHUB_RUN_ID:+/runs/${GITHUB_RUN_ID}}}"
: "${GITHUB_REF:=$(git symbolic-ref HEAD)}"
BRANCH=${GITHUB_REF#refs/heads/}
BRANCH_URL="${REPO_URL}/tree/${BRANCH}"

# prop extracts property from JSON object.
# prop('{"name": "Tricia", "age": 42}', age)
# 42
prop() {
    echo "$1" | jq -r ".$2"
}

CURL_HEADERS=(-H "Accept: application/vnd.github.groot-preview+json")
if [[ -n "${GITHUB_TOKEN-}" ]]; then
    CURL_HEADERS+=(-H "Authorization: token ${GITHUB_TOKEN}")
fi

COMMIT_URL="${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/commits/${GITHUB_SHA}"
pr=$(curl -fsSL "${CURL_HEADERS[@]}" "${COMMIT_URL}/pulls" |
    jq '.[0] | {url: .html_url, number, title: .title, author: .user.login}' || echo '{}')
if [[ $(prop "${pr}" number) != null ]]; then
    PR="PR #$(prop "${pr}" number)"
    PR_URL=$(prop "${pr}" url)
    PR_TITLE=$(prop "${pr}" title)
    PR_AUTHOR=$(prop "${pr}" author)
else
    commit=$(curl -fsSL "${CURL_HEADERS[@]}" "${COMMIT_URL}" |
        jq '{url: .html_url, message: .commit.message, author: .author.login}' || echo '{}')
    PR="Commit \`${GITHUB_SHA::7}\`"
    if [[ $(prop "${commit}" url) != null ]]; then
        PR_URL=$(prop "${commit}" url)
        PR_TITLE=$(prop "${commit}" message | head -n 1)
        PR_AUTHOR=$(prop "${commit}" author)
    else
        PR_URL="${REPO_URL}"
        PR_TITLE=$(git show -s --pretty=format:%s)
        PR_AUTHOR=$(git show -s --pretty=format:%an)
    fi
fi

curl -fsSL -d @- "${SLACK_HOOK_URL}" <<EOF
{
 "icon_url": "${PICTURE_BASE_URL}/failed-build.png",
 ${CHANNEL:+"\"channel\": \"${CHANNEL}\","}
 "username": "GitHub",
 "text": "${SLACK_TEXT-}",
 "attachments": [
      {
          "fallback": "Build failure on ${BRANCH}",
          "color": "danger",
          "fields": [
            {
                "value": "\
*<${BUILD_URL}|Build Failure>* on \`<${BRANCH_URL}|${REPO}:${BRANCH}>\`\n\
<${PR_URL}|${PR}> - ${PR_TITLE} \`@${PR_AUTHOR}\`"
            }
          ],
          "footer": "<${REPO_URL}|${REPO}>",
          "footer_icon": "${PICTURE_BASE_URL}/footer-logo.png"
      }
  ]
}
EOF
