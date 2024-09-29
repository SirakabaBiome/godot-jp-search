#!/bin/bash

# 変換対象のディレクトリを指定（実行時に引数として渡す）
target_dir="/home/folta/Documents/GitHub/folta-blog/work/thumb"

# ディレクトリが存在しない場合はエラーメッセージを表示して終了
if [ ! -d "$target_dir" ]; then
    echo "指定されたディレクトリが存在しません: $target_dir"
    exit 1
fi

# rsvg-convertがインストールされているか確認
if ! command -v rsvg-convert &> /dev/null; then
    echo "rsvg-convertがインストールされていません。インストールしてから再実行してください。"
    echo "インストールコマンド: sudo apt-get install librsvg2-bin"
    exit 1
fi

# SVGファイルを検索して処理
find "$target_dir" -type f -name "*.svg" | while read -r svg_file; do
    # 出力するPNGファイル名を生成
    png_file="${svg_file%.svg}.png"
    
    # SVGをPNGに変換（短辺を960pxに設定）
    rsvg-convert -w 960 -h 960 --keep-aspect-ratio "$svg_file" -o "$png_file"
    
    # 変換が成功した場合、元のSVGファイルを削除
    if [ $? -eq 0 ]; then
        rm "$svg_file"
        echo "変換完了: $svg_file -> $png_file"
    else
        echo "変換失敗: $svg_file"
    fi
done

echo "すべての処理が完了しました。"