#!/bin/bash

# 入力ファイルと出力ファイルの名前を設定
input_file="addon-input.txt"
output_file="addon-output.json"
editable_file="addon-editable-data.json"
github_token_file="/home/folta/Documents/token/github_token.txt"
gitlab_token_file=""
#readme_dir="ReadMe"

# エラーログファイルの設定
error_log="jq_errors.log"

is_ignore_readme=true
is_ignore_file_structure=true
is_ignore_languages=false

# ReadMeディレクトリが存在しない場合は作成
#mkdir -p "$readme_dir"

# GitHubとGitLabのトークンを読み込む
if [ -f "$github_token_file" ]; then
    github_token=$(cat "$github_token_file")
fi

if [ -f "$gitlab_token_file" ]; then
    gitlab_token=$(cat "$gitlab_token_file")
fi

# 編集可能なJSONファイルが存在しない場合、新規作成
if [ ! -f "$editable_file" ]; then
    echo "{}" > "$editable_file"
fi

# JSONファイルの開始
echo "{" > "$output_file"

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

# プログレスバーを表示
echo "処理中..."
total_repos=$(wc -l < "$input_file")
current_repo=0

while IFS= read -r full_repo || [[ -n "$full_repo" ]]; do
    # リポジトリ名から不要な空白を削除
    full_repo=$(echo "$full_repo" | tr -d '[:space:]')

    # 末尾が/の場合は削除
    if [[ $full_repo == */ ]]; then
        full_repo="${full_repo::-1}"
    fi

    # 初期値を設定
    repo_type="unknown"
    repo=$full_repo
    updated_at='""'
    owner='"unknown"'
    default_branch='"main"'
    stars=0
    topics="[]"
    languages="{}"
    file_structure="[]"
    readme=""
    license='"Unknown"'

    # リポジトリタイプ (GitHub or GitLab or Bitbucket) に応じてAPIのURLを設定
    if [[ $full_repo == *"github.com"* ]]; then
        repo_type="github"
        repo="${full_repo#https://github.com/}"
        api_url="https://api.github.com/repos/$repo"
        topics_url="${api_url}/topics"
        languages_url="${api_url}/languages"
        readme_url="${api_url}/readme"
        trees_url="${api_url}/git/trees/main?recursive=1"
        token=$github_token
        token_type="token"
    elif [[ $full_repo == *"gitlab.com"* ]]; then
        repo_type="gitlab"
        repo="${full_repo#https://gitlab.com/}"
        repo_id=$(echo $repo | sed 's/\//%2F/g')
        api_url="https://gitlab.com/api/v4/projects/${repo_id}"
        topics_url="${api_url}"
        languages_url="${api_url}/languages"
        readme_url="${api_url}/repository/files/README.md/raw?ref=main"
        trees_url="${api_url}/repository/tree?recursive=true"
        token=$gitlab_token
        token_type="Bearer"
    elif [[ $full_repo == *"bitbucket.org"* ]]; then
        repo_type="bitbucket"
        repo="${full_repo#https://bitbucket.org/}"
        api_url="https://api.bitbucket.org/2.0/repositories/$repo"
        topics_url="${api_url}"
        trees_url="${api_url}/src/main?pagelen=1000"
        token=""
        token_type=""
    else
        # リポジトリタイプが不明な場合はhttp://, https://, git@ で始まる部分をカットする
        repo=$(echo "$full_repo" | sed -E 's/^(http:\/\/|https:\/\/|git@)//')
    fi

    if [ "$repo_type" != "unknown" ]; then
        # リポジトリ情報を取得
        repo_info=$(fetch_api "$api_url" "$token" "$token_type")
        topics=$(fetch_api "$topics_url" "$token" "$token_type")

        if [ "$repo_type" = "github" ]; then
          # ライセンス情報を取得
            license_info=$(fetch_api "${api_url}/license" "$token" "$token_type")
            # GitHubの場合はリポジトリ情報と言語情報を取得
            if [ "$is_ignore_languages" = false ]; then
                languages=$(fetch_api "$languages_url" "$token" "$token_type")
            fi
            if [ "$is_ignore_readme" = false ]; then
                readme=$(fetch_api "$readme_url" "$token" "$token_type")
            fi
        elif [ "$repo_type" = "gitlab" ]; then
            # GitLabの場合はリポジトリ情報と言語情報を取得
            if [ "$is_ignore_languages" = false ]; then
                languages=$(fetch_api "$languages_url" "$token" "$token_type")
            fi
            if [ "$is_ignore_readme" = false ]; then
                readme=$(fetch_api "$readme_url" "$token" "$token_type")
            fi
        fi

        # 情報を抽出
        if [ "$repo_type" = "github" ]; then
            updated_at=$(run_jq "$repo" '.pushed_at // empty' "$repo_info")
            owner=$(run_jq "$repo" '.owner.login // empty' "$repo_info")
            default_branch=$(run_jq "$repo" '.default_branch // empty' "$repo_info")
            stars=$(run_jq "$repo" '.stargazers_count // 0' "$repo_info")
            topics=$(run_jq "$repo" '.names // []' "$topics")
            license=$(run_jq "$repo" '.license.spdx_id // "Unknown"' "$license_info")
        elif [ "$repo_type" = "gitlab" ]; then
            updated_at=$(run_jq "$repo" '.last_activity_at // empty' "$repo_info")
            owner=$(run_jq "$repo" '.namespace.path // empty' "$repo_info")
            default_branch=$(run_jq "$repo" '.default_branch // empty' "$repo_info")
            stars=$(run_jq "$repo" '.star_count // 0' "$repo_info")
            topics=$(run_jq "$repo" '.tag_list // []' "$repo_info")
        elif [ "$repo_type" = "bitbucket" ]; then
            updated_at=$(run_jq "$repo" '.updated_on // empty' "$repo_info")
            owner=$(run_jq "$repo" '.owner.display_name // empty' "$repo_info")
            default_branch=$(run_jq "$repo" '.mainbranch.name // empty' "$repo_info")
            stars=0  # Bitbucketにはスター機能がないようです
            topics="[]"  # トピックがない場合は空の配列を設定
        fi

        # ファイル構造を取得
        if [ "$is_ignore_file_structure" = false ]; then
          file_structure=$(fetch_api "$trees_url" "$token" "$token_type" | run_jq "$repo" '.tree[] | select(.type == "blob") | .path')
        fi
    fi

    # JSONオブジェクトに情報を追加
    echo "  \"$repo\": {" >> "$output_file"
    echo "    \"repo_type\": \"$repo_type\"," >> "$output_file"
    echo "    \"last_updated\": $updated_at," >> "$output_file"
    echo "    \"owner\": $owner," >> "$output_file"
    echo "    \"default_branch\": $default_branch," >> "$output_file"
    echo "    \"stars\": $stars," >> "$output_file"
    echo "    \"license\": $license," >> "$output_file"

    # 言語を追加
    if [ "$is_ignore_languages" = false ]; then
      echo "    \"languages\": " >> "$output_file"
      run_jq "$repo" '.' "$languages" >> "$output_file"
      echo "    ," >> "$output_file"
    fi

    if [ "$is_ignore_readme" = false ]; then
    # ファイル構造をJSONに追加
    echo "    \"file_structure\": [" >> "$output_file"
    echo "$file_structure" | sed 's/^/      "/' | sed 's/$/",/' >> "$output_file"
    # 最後のカンマを削除
    sed -i '$ s/,$//' "$output_file"
    echo "    ]" >> "$output_file"
    echo "    ," >> "$output_file"
    fi

    # トピックを追加
    echo "    \"topics\": " >> "$output_file"
    echo "$topics" >> "$output_file"
    echo "  }," >> "$output_file"

    # READMEの内容をReadMeディレクトリ内の別ファイルに出力
    if [ "$is_ignore_readme" = false ]; then
      readme_file="$readme_dir/${repo//\//_}_README.md"
      echo "$readme" > "$readme_file"
    fi

    # idとurlの生成
    escaped_id=$(echo "$repo" | sed 's/[^a-zA-Z0-9]/_/g')
    repo_url="$full_repo"

    # タイトルは頭大文字、スペースに置換する
    if [ "$repo_type" = "github" ] || [ "$repo_type" = "gitlab" ]; then
      # GitHub,GitLabではauthor部分に当たる部分を削除してから処理
      title=$(echo "$repo" | sed -e 's/\b\(.\)/\u\1/g' -e 's/\// /g' -e 's/^[^/]*\///')
    else
      title=$(echo "$repo" | sed -e 's/\b\(.\)/\u\1/g' -e 's/\// /g')
    fi

    # 現在の日時を取得
    current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # 編集可能なJSONファイルを更新
    if ! jq -e ".[\"$repo\"]" "$editable_file" > /dev/null 2>> "$error_log"; then
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
            "has_thumbnail": true,
            "images": [],
            "article_urls": [],
            "license_override": "",
            "listed_at": $current_date
        }}' "$editable_file" > "$tmp" 2>> "$error_log"; then
            echo "Error updating $editable_file for repo $repo" >> "$error_log"
        else
            mv "$tmp" "$editable_file"
        fi
    fi

    # プログレスバーを表示
    current_repo=$((current_repo + 1))
    echo -ne "処理中... $current_repo / $total_repos\r"

done < "$input_file"

# 最後のカンマを削除し、JSONファイルを閉じる
sed -i '$ s/,$//' "$output_file"
echo "}" >> "$output_file"

# 出力ファイルと編集用ファイルの更新日時を同期
touch -r "$output_file" "$editable_file"

echo "処理が完了しました。結果は $output_file に保存されました。"
echo "各リポジトリのREADMEは $readme_dir ディレクトリ内に [リポジトリ名]_README.md として保存されました。"
echo "手動編集用のデータは $editable_file に保存されました。"
echo "出力ファイルと編集用ファイルの更新日時を同期しました。"
echo "jqのエラーログは $error_log に保存されました。"