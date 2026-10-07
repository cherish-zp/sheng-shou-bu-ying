#!/usr/bin/env bash
# 把 GitHub Release 的正文与附件同步到 Gitee Release（CI sync-gitee job 的本地兜底）。
#
# 背景：Gitee WAF 对 GitHub 托管 runner 的数据中心 IP 返回 HTTP 200 的 HTML 人机
# 验证页（假 200），CI 侧同步不可靠；本机在国内网络直连 Gitee 无障碍，用它兜底。
#
# 用法：
#   GITEE_TOKEN=<gitee私人令牌> ./scripts/sync-gitee-release.sh v1.0.0
#
# 幂等：Gitee Release 存在则复用并对齐正文，同名附件跳过，单附件重试 5 次。
set -euo pipefail

TAG="${1:?usage: GITEE_TOKEN=... $0 v1.0.0}"
GITEE_TOKEN="${GITEE_TOKEN:?GITEE_TOKEN is required}"
GITHUB_REPO="${GITHUB_REPO:-cherish-zp/sheng-shou-bu-ying}"
GITEE_REPO="${GITEE_REPO:-princess-zp/sheng-shou-bu-ying}"
APP_NAME="圣手捕影"

GITEE_API="https://gitee.com/api/v5/repos/${GITEE_REPO}"
GH_API="https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${TAG}"

# 1) GitHub Release（公开仓库，无需认证）
echo "▸ 读取 GitHub Release ${TAG} ..."
GH_JSON="$(curl -sf --connect-timeout 20 "${GH_API}")" || {
  echo "✗ GitHub Release 不存在或网络失败：${GH_API}"; exit 1; }
BODY="$(printf '%s' "$GH_JSON" | jq -r '.body // ""')"
ASSET_COUNT="$(printf '%s' "$GH_JSON" | jq '.assets | length')"
echo "  正文 $(printf '%s' "$BODY" | wc -c | tr -d ' ') 字节，附件 ${ASSET_COUNT} 个"

# 2) Gitee Release：存在则复用并对齐正文，不存在则创建
#    所有响应必须通过 jq 校验为 JSON——WAF 的 HTML 假 200 页在此被识破。
echo "▸ 探测 Gitee Release ..."
RELEASE_JSON="$(curl -s --connect-timeout 20 \
  "${GITEE_API}/releases/tags/${TAG}?access_token=${GITEE_TOKEN}")"
RELEASE_ID="$(printf '%s' "$RELEASE_JSON" | jq -e -r '.id // empty' 2>/dev/null || true)"

if [ -z "$RELEASE_ID" ]; then
  echo "▸ 不存在，创建 Gitee Release ${TAG} ..."
  PAYLOAD="$(jq -n --arg tag "$TAG" --arg name "${APP_NAME} ${TAG}" --arg body "$BODY" \
    '{tag_name:$tag, name:$name, body:$body, target_commitish:"main", prerelease:false}')"
  CREATE_JSON="$(curl -s --connect-timeout 20 -X POST "${GITEE_API}/releases?access_token=${GITEE_TOKEN}" \
    -H 'Content-Type: application/json' -d "$PAYLOAD")"
  RELEASE_ID="$(printf '%s' "$CREATE_JSON" | jq -e -r '.id // empty' 2>/dev/null || true)"
  [ -n "$RELEASE_ID" ] || { echo "✗ 创建失败，响应：$(printf '%s' "$CREATE_JSON" | head -c 300)"; exit 1; }
else
  echo "▸ 已存在（id=${RELEASE_ID}），对齐正文 ..."
  curl -s --connect-timeout 20 -X PATCH "${GITEE_API}/releases/${RELEASE_ID}?access_token=${GITEE_TOKEN}" \
    -H 'Content-Type: application/json' \
    -d "$(jq -n --arg name "${APP_NAME} ${TAG}" --arg body "$BODY" '{name:$name, body:$body}')" \
    | jq -e '.id' >/dev/null 2>&1 && echo "  正文已更新" || echo "  ⚠️ 正文更新失败（继续同步附件）"
fi
echo "  Gitee Release id=${RELEASE_ID}"

# 3) 幂等上传附件
EXISTING="$(printf '%s' "$RELEASE_JSON" | jq -r '.assets[].name' 2>/dev/null || true)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
FAIL=0
while IFS=$'\t' read -r NAME URL; do
  [ -n "$URL" ] || continue
  if printf '%s\n' "$EXISTING" | grep -Fxq "$NAME"; then
    echo "  跳过已存在附件：${NAME}"; continue
  fi
  echo "▸ 下载 ${NAME} ..."
  curl -sfL --connect-timeout 20 --retry 3 -o "${WORK}/${NAME}" "$URL" || {
    echo "  ✗ 下载失败：${NAME}"; FAIL=1; continue; }
  OK=0
  for attempt in 1 2 3 4 5; do
    if curl -sf --connect-timeout 20 -X POST \
         "${GITEE_API}/releases/${RELEASE_ID}/attach_files?access_token=${GITEE_TOKEN}" \
         -F "file=@${WORK}/${NAME}" | jq -e . >/dev/null 2>&1; then
      echo "  ✓ 已上传：${NAME}"; OK=1; break
    fi
    echo "  上传失败（第 ${attempt}/5 次）：${NAME}"
    [ "$attempt" -lt 5 ] && sleep 15
  done
  [ "$OK" = 1 ] || FAIL=1
done < <(printf '%s' "$GH_JSON" | jq -r '.assets[] | [.name, .browser_download_url] | @tsv')

[ "$FAIL" = 0 ] || { echo "✗ 部分附件同步失败，修复后重跑本脚本即可（幂等）"; exit 1; }
echo "✓ Gitee 同步完成：https://gitee.com/${GITEE_REPO}/releases/tag/${TAG}"
