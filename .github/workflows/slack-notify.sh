#!/usr/bin/env bash

if ! [[ -f "${GITHUB_EVENT_PATH}" ]]; then
    echo "GITHUB_EVENT_PATH not defined or doesn't exist" >&2
    exit 1
fi

read -r slack_token
HOOK_URL="https://hooks.slack.com/services/${slack_token}"

event_field() {
    jq -r ".$1" "${GITHUB_EVENT_PATH}"
}

pr_field() {
    echo "$1" | jq -r ".$2"
}

REPO=$(event_field repository.name)
REPO_FULLNAME=$(event_field repository.full_name)
REPO_URL=$(event_field repository.html_url)

BRANCH_URL="${REPO_URL}/blob/${BRANCH}"
BUILD_URL=$(event_field target_url)

PR="Commit \`${GITHUB_SHA::7}\`"
PR_URL=$(event_field commit.html_url)
PR_MESSAGE=$(event_field commit.commit.message | head -n 1)
PR_AUTHOR=$(event_field commit.commit.author.name)

pr=$(curl -H "Accept: application/vnd.github.groot-preview+json" \
    "https://api.github.com/repos/${REPO_FULLNAME}/commits/${GITHUB_SHA}/pulls" |
    jq '.[0] | {url: html_url, number, message: .title, author: .user.login}')
if [[ "$(echo "${pr:-{}}" | jq .number)" != null ]]; then
    PR="PR #$(pr_field "${pr}" number)"
    PR_URL=$(pr_field "${pr}" url)
    PR_MESSAGE=$(pr_field "${pr}" message)
    PR_AUTHOR=$(pr_field "${pr}" author)
fi



curl -d @- "${HOOK_URL}" <<EOF
{
 "icon_url": "https://github.com/juliaogris/pic/raw/master/github/failed-build.png",
 ${CHANNEL:+"\"channel\": ${CHANNEL},"}
 "username": "GitHub",
 "text": "${SLACK_TEXT}",
 "attachments": [
      {
          "fallback": "Build failure on ${BRANCH}",
          "color": "danger",
          "fields": [
            {
                "value": "\
*<${BUILD_URL}|Build Failure>* on \`<${BRANCH_URL}|${REPO}:${BRANCH}>\`\n\
<${PR_URL}|${PR}> - ${PR_MESSAGE} \`@${PR_AUTHOR}\`"
            }
          ],
          "footer": "<${REPO_URL}|${REPO}>",
          "footer_icon": "https://github.com/juliaogris/pic/raw/master/github/footer-logo.png"
      }
  ]
}
EOF
