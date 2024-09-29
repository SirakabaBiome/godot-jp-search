#!/bin/bash

# 保存先ディレクトリを設定（デフォルトは現在のディレクトリ）
SAVE_DIR="${1:-.}"

# JSONファイルのパスを設定（必要に応じて変更してください）
JSON_FILE="/home/folta/Documents/GitHub/folta-blog/work/addon-editable-data.json"

# ディレクトリが存在しない場合は作成
mkdir -p "$SAVE_DIR"

# ディレクトリ名を取得する関数
get_dir_name() {
    local dir="$1"
    if [ "$dir" = "." ]; then
        echo "$(basename "$(pwd)")"
    else
        echo "$(basename "$dir")"
    fi
}

# ディレクトリ名を取得
DIR_NAME=$(get_dir_name "$SAVE_DIR")

# 利用可能なファイル名を生成する関数
generate_filename() {
    local base_name="$1"
    local extension="$2"
    local full_path
    local counter=1

    if [[ "${extension,,}" =~ ^(png|jpe?g)$ ]]; then
        # PNG, JPG, JPEGファイルの場合、WebPファイルの存在をチェック
        while true; do
            if [ $counter -eq 1 ]; then
                full_path="$SAVE_DIR/$base_name.webp"
            else
                full_path="$SAVE_DIR/${base_name}_${counter}.webp"
            fi
            if [[ ! -e "$full_path" ]]; then
                echo "$(basename "${full_path%.*}").$extension"
                return
            fi
            ((counter++))
        done
    else
        # その他のファイルの場合、通常の重複チェック
        while true; do
            if [ $counter -eq 1 ]; then
                full_path="$SAVE_DIR/$base_name.$extension"
            else
                full_path="$SAVE_DIR/${base_name}_${counter}.$extension"
            fi
            if [[ ! -e "$full_path" ]]; then
                echo "$(basename "$full_path")"
                return
            fi
            ((counter++))
        done
    fi
}

# JSONファイルを更新する関数
update_json() {
    local id="$1"
    local extension="$2"
    
    # jqを使用してJSONファイルを更新
    jq --arg id "$id" --arg ext "$extension" '
    to_entries | map(
        if .value.id == $id then
            .value.images += [$ext] | 
            .value.images |= unique
        else . end
    ) | from_entries
    ' "$JSON_FILE" > "${JSON_FILE}.tmp" && mv "${JSON_FILE}.tmp" "$JSON_FILE"
    echo "JSONファイルを更新しました。ID: $id, 追加された拡張子: $extension"
}

# ファイルをダウンロードし、必要に応じて変換する関数
download_and_convert_file() {
    local URL="$1"
    
    # URLからファイル名と拡張子を抽出
    ORIGINAL_FILENAME=$(basename "$URL")
    EXTENSION="${ORIGINAL_FILENAME##*.}"
    
    # クリップボードから文字列を取得（IDとして使用）
    ID=$(xclip -selection clipboard -o)
    
    # IDが空でない場合、それをファイル名のベースとして使用
    if [ -n "$ID" ]; then
        # IDから不適切な文字を削除
        FILENAME_BASE=$(echo "$ID" | tr -cd '[:alnum:]._-')
        
        # 拡張子が存在する場合は追加、そうでない場合は元のファイル名を使用
        if [ -n "$EXTENSION" ] && [ "$EXTENSION" != "$ORIGINAL_FILENAME" ]; then
            FILENAME=$(generate_filename "$FILENAME_BASE" "$EXTENSION")
        else
            FILENAME=$(generate_filename "$ORIGINAL_FILENAME" "")
        fi
    else
        # IDが空の場合、URLからのファイル名をそのまま使用
        FILENAME=$(generate_filename "${ORIGINAL_FILENAME%.*}" "${ORIGINAL_FILENAME##*.}")
    fi
    
    # ファイルをダウンロード
    wget -O "$SAVE_DIR/$FILENAME" "$URL"
    
    if [ $? -eq 0 ]; then
        echo "ファイル '$FILENAME' を $DIR_NAME ディレクトリにダウンロードしました。"
        
        # PNG, JPG, JPEGファイルの場合、WebPに変換
        if [[ "${FILENAME,,}" =~ \.(png|jpe?g)$ ]]; then
            WEBP_FILENAME="${FILENAME%.*}.webp"
            if command -v cwebp &> /dev/null; then
                cwebp "$SAVE_DIR/$FILENAME" -o "$SAVE_DIR/$WEBP_FILENAME"
                if [ $? -eq 0 ]; then
                    echo "ファイルをWebPに変換しました: $WEBP_FILENAME"
                    rm "$SAVE_DIR/$FILENAME"  # 元のファイルを削除
                    FILENAME="$WEBP_FILENAME"
                    EXTENSION="webp"
                else
                    echo "WebPへの変換に失敗しました。元のファイルを保持します。"
                fi
            else
                echo "cwebpコマンドが見つかりません。WebPへの変換をスキップします。"
            fi
        fi
        
        # JSONファイルを更新
        update_json "$ID" "$EXTENSION"
    else
        echo "ダウンロードに失敗しました。"
    fi
}

# クリップボードの内容を表示する関数
display_clipboard() {
    local clipboard_content
    local previous_content=""
    
    clear
    echo "URLをドロップしてください（保存先: $DIR_NAME）（終了するには 'q' を入力）: "
    
    while true; do
        clipboard_content=$(xclip -selection clipboard -o 2>/dev/null)
        if [ "$clipboard_content" != "$previous_content" ]; then
            echo -ne "\rクリップボード (ID): ${clipboard_content:0:50}                    \n"
            if [ ${#clipboard_content} -gt 50 ]; then
                echo -ne "             ${clipboard_content:50:50}                    \n"
            else
                echo -ne "                                                           \n"
            fi
            echo -ne "\033[2A" # カーソルを2行上に移動
            previous_content="$clipboard_content"
        fi
        sleep 0.5
    done
}

# メインループ
display_clipboard &
DISPLAY_PID=$!

while true; do
    read -r URL
    
    if [[ $URL == "q" ]]; then
        kill $DISPLAY_PID
        wait $DISPLAY_PID 2>/dev/null
        clear
        echo "プログラムを終了します。"
        break
    elif [[ -n $URL ]]; then
        kill $DISPLAY_PID
        wait $DISPLAY_PID 2>/dev/null
        clear
        
        download_and_convert_file "$URL"
        echo # 空行を挿入して読みやすくする
        
        # クリップボード表示を再開
        display_clipboard &
        DISPLAY_PID=$!
    fi
done

# 終了時にバックグラウンドプロセスを確実に終了
kill $DISPLAY_PID 2>/dev/null
wait $DISPLAY_PID 2>/dev/null
