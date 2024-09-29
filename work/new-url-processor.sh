#!/bin/bash

# 入力ファイルと出力ファイルの名前を設定
input_file="input.txt"
editable_file="editable_data.json"
github_token_file="github_token.txt"
gitlab_token_file="gitlab_token.txt"
error_log="jq_errors.log"
added_repos_log="added_repos.log"

# 追加されたリポジトリのログファイルを初期化
> "$added_repos_log"

# GitHubとGitLabのトークンを読み込む
if [ -f "$github_token_file" ]; then
    github_token=$(cat "$github_token_file")
fi

if [ -f "$gitlab_token_file" ]; then
    gitlab_token=$(cat "$gitlab_token_file")
fi

# エラーログ関数の定義
log_error() {
    local repo="$1"
    local command="$2"
    local error="$3"
    local object="$4"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error in repo '$repo' - Command: $command" >> "$error_log"
    echo "Error message: $error" >> "$error_log"
    echo "Object: $object" >> "$error_log"
    echo "---" >> "$error_log"
}

# jqコマンドを実行し、エラーをログに記録する関数
run_jq() {
    local repo="$1"
    local command="$2"
    local input="$3"
    local result
    local exit_status

    result=$(echo "$input" | jq -e "$command" 2>&1)
    exit_status=$?

    if [ $exit_status -ne 0 ]; then
        log_error "$repo" "$command" "$result" "$input"
        echo ""
    else
        echo "$result"
    fi
}

# API呼び出しを行う関数
fetch_api() {
    local url=$1
    local token=$2
    local token_type=$3

    if [ -n "$token" ]; then
        curl -s -H "Authorization: $token_type $token" "$url"
    else
        curl -s "$url"
    fi
}

# 入力ファイルの各行を処理
while IFS= read -r full_repo || [[ -n "$full_repo" ]]; do
    # リポジトリ名から不要な空白を削除
    full_repo=$(echo "$full_repo" | tr -d '[:space:]')

    # 末尾が/の場合は削除
    if [[ $full_repo == */ ]]; then
        full_repo="${full_repo::-1}"
    fi

    # 既存のeditable_data.jsonにURLが存在するかチェック
    if jq -e ".[] | select(.url == \"$full_repo\")" "$editable_file" > /dev/null 2>&1; then
#        echo "URL already exists in $editable_file: $full_repo"
        continue
    fi

    # 初期値を設定
    repo_type="unknown"
    repo=$full_repo

    # リポジトリタイプ (GitHub or GitLab or Bitbucket) に応じてAPIのURLを設定
    if [[ $full_repo == *"github.com"* ]]; then
        repo_type="github"
        repo="${full_repo#https://github.com/}"
        api_url="https://api.github.com/repos/$repo"
        token=$github_token
        token_type="token"
    elif [[ $full_repo == *"gitlab.com"* ]]; then
        repo_type="gitlab"
        repo="${full_repo#https://gitlab.com/}"
        repo_id=$(echo $repo | sed 's/\//%2F/g')
        api_url="https://gitlab.com/api/v4/projects/${repo_id}"
        token=$gitlab_token
        token_type="Bearer"
    elif [[ $full_repo == *"bitbucket.org"* ]]; then
        repo_type="bitbucket"
        repo="${full_repo#https://bitbucket.org/}"
        api_url="https://api.bitbucket.org/2.0/repositories/$repo"
        token=""
        token_type=""
    else
        repo=$(echo "$full_repo" | sed -E 's/^(http:\/\/|https:\/\/|git@)//')
    fi

    # リポジトリ情報を取得
    if [ "$repo_type" != "unknown" ]; then
        repo_info=$(fetch_api "$api_url" "$token" "$token_type")
    fi

    # タイトルは頭大文字、スペースに置換する
    if [ "$repo_type" = "github" ] || [ "$repo_type" = "gitlab" ]; then
        # GitHub,GitLabではauthor部分に当たる部分を削除してから処理
        title=$(echo "$repo" | sed -e 's/\b\(.\)/\u\1/g' -e 's/\// /g' -e 's/^[^/]*\///')
    else
        title=$(echo "$repo" | sed -e 's/\b\(.\)/\u\1/g' -e 's/\// /g')
    fi

    # idとurlの生成
    escaped_id=$(echo "$repo" | sed 's/[^a-zA-Z0-9]/_/g')
    repo_url="$full_repo"

    # 現在の日時を取得
    current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # 編集可能なJSONファイルを更新
    tmp=$(mktemp)
    if ! jq --arg repo "$repo" --arg escaped_id "$escaped_id" --arg repo_url "$repo_url" --arg repo_type "$repo_type" --arg title "$title" --arg current_date "$current_date" '. + {($repo): {
        "id": $escaped_id,
        "url": $repo_url,
        "repo_type": $repo_type,
        "title": $title,
        "summary_ja": "",
        "summary_ko": "",
        "summary_en": "",
        "point": 0,
        "fav_point": 0,
        "tags": ["3d","needcheck"],
        "is_edited": false,
        "is_exists_assetlib": true,
        "assetlib_path": "",
        "godot_version": "",
        "thumbnails": [$escaped_id],
        "article_urls": [],
        "license_override": "",
        "listed_at": $current_date
    }}' "$editable_file" > "$tmp" 2>> "$error_log"; then
        echo "Error updating $editable_file for repo $full_repo" >> "$error_log"
    else
        mv "$tmp" "$editable_file"
        echo "Added new URL to $editable_file: $full_repo"
        # 追加されたリポジトリをログに記録
        echo "$title: $full_repo" >> "$added_repos_log"
    fi

done < "$input_file"

echo "処理が完了しました。新規URLが $editable_file に追加されました。"
echo "jqのエラーログは $error_log に保存されました。"
echo "追加されたリポジトリのリストは $added_repos_log に保存されました。"

# 追加されたリポジトリのリストを表示
echo "追加されたリポジトリ:"
cat "$added_repos_log"