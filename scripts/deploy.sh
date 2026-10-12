#!/usr/bin/env bash
# master の内容のうち、.deploykeep に列挙したパスだけを deploy ブランチへ反映する。
#
# 環境変数(すべて任意):
#   SOURCE_DIR     master をチェックアウトしたディレクトリ (default: source)
#   DEPLOY_DIR     deploy ブランチ用 worktree の場所       (default: deploy)
#   DEPLOY_BRANCH  反映先ブランチ名                        (default: deploy)
#   KEEP_FILE      対象リスト(SOURCE_DIR からの相対)      (default: .deploykeep)

set -euo pipefail

SOURCE_DIR="${SOURCE_DIR:-source}"
DEPLOY_DIR="${DEPLOY_DIR:-deploy}"
DEPLOY_BRANCH="${DEPLOY_BRANCH:-deploy}"
KEEP_FILE="${KEEP_FILE:-.deploykeep}"

# リストファイルが無い場合に使う既定の対象
DEFAULT_TARGETS=(functions public src index.html)

TARGETS=()

git_config() {
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
}

# ---- 対象リストの読み込み ---------------------------------------------------
# - '#' 以降はコメント(行頭・行末どちらも可)
# - 空行は無視
# - 前後の空白、先頭の ./ 、末尾の / は除去
# - 絶対パスと '..' を含むパスは安全のため無視
read_targets() {
  local file="$SOURCE_DIR/$KEEP_FILE"

  if [ ! -f "$file" ]; then
    echo "info: $KEEP_FILE not found. Using defaults: ${DEFAULT_TARGETS[*]}"
    TARGETS=("${DEFAULT_TARGETS[@]}")
    return 0
  fi

  local line
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"            # コメント除去
    line="${line//$'\r'/}"        # CRLF 対策
    line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -z "$line" ] && continue

    line="${line#./}"
    while [[ "$line" == */ ]]; do line="${line%/}"; done
    [ -z "$line" ] && continue

    case "$line" in
      /*|..|../*|*/..|*/../*)
        echo "warn: ignoring unsafe path: $line"
        continue
        ;;
    esac

    TARGETS+=("$line")
  done < "$file"

  echo "info: targets from $KEEP_FILE: ${TARGETS[*]:-(none)}"
}

# ---- deploy ブランチの worktree を用意 --------------------------------------
prepare_worktree() {
  (
    cd "$SOURCE_DIR"
    git_config
    if git ls-remote --exit-code --heads origin "$DEPLOY_BRANCH" >/dev/null 2>&1; then
      git fetch origin "$DEPLOY_BRANCH"
      git worktree add -B "$DEPLOY_BRANCH" "../$DEPLOY_DIR" "origin/$DEPLOY_BRANCH"
    else
      echo "info: branch '$DEPLOY_BRANCH' not found. Creating an orphan branch."
      git worktree add --detach "../$DEPLOY_DIR"
      cd "../$DEPLOY_DIR"
      git checkout --orphan "$DEPLOY_BRANCH"
      git rm -rf . >/dev/null 2>&1 || true
      git clean -fdx >/dev/null 2>&1 || true
    fi
  )
}

# ---- 対象をコピー -----------------------------------------------------------
# deploy 側は一度空にしてからコピーするので、
# master 側で消したファイルや、リストから外したパスも反映される。
copy_targets() {
  find "$DEPLOY_DIR" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +

  local src_abs dst_abs
  src_abs="$(cd "$SOURCE_DIR" && pwd)"
  dst_abs="$(cd "$DEPLOY_DIR" && pwd)"

  # ワイルドカード(*, ?, [..], **)を SOURCE_DIR 基準で展開する
  #   nullglob: 一致なしなら空に展開(エラーにしない)
  #   dotglob : * でドットファイルも対象にする(.git は後で除外)
  #   globstar: ** で再帰
  shopt -s nullglob dotglob globstar

  local p match count
  for p in "${TARGETS[@]}"; do
    count=0
    # サブシェル内で IFS を空にして、パス中の空白で分割されないようにする
    # (グロブ展開は有効のまま)。結果は NUL 区切りで受け取る。
    while IFS= read -r -d '' match; do
      case "$match" in .git|.git/*) continue ;; esac
      # ワイルドカードを含まないパスは、存在しなくても展開されず文字列のまま残るため、
      # 実在しないものはここでスキップする(エラーにしない)
      [ -e "$src_abs/$match" ] || continue
      if [ -d "$src_abs/$match" ]; then
        mkdir -p "$dst_abs/$match"
        cp -r "$src_abs/$match/." "$dst_abs/$match/"
      else
        mkdir -p "$dst_abs/$(dirname "$match")"
        cp "$src_abs/$match" "$dst_abs/$match"
      fi
      count=$((count + 1))
    done < <(cd "$src_abs" && IFS= && for m in $p; do printf '%s\0' "$m"; done)

    if [ "$count" -gt 0 ]; then
      echo "copied: $p ($count match)"
    else
      echo "skip (not found): $p"
    fi
  done

  shopt -u nullglob dotglob globstar
}

# ---- コミット & push --------------------------------------------------------
commit_and_push() {
  cd "$DEPLOY_DIR"
  git_config
  git add -A
  if git diff --cached --quiet; then
    echo "No changes to deploy."
    return 0
  fi
  git commit -m "Deploy from master (${GITHUB_SHA:0:7})"
  git push origin "HEAD:$DEPLOY_BRANCH"
}

main() {
  read_targets
  prepare_worktree
  copy_targets
  commit_and_push
}

main "$@"
