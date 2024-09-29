#!/bin/bash

output_file="addon-output.json"
editable_file="addon-editable-data.json"
merged_file="../static/data/addon.json"
tag_translation_file="tag_translation.json"
tag_translation_file_copy_to="../static/data/tag_translation.json"

# 除外するタグのリスト（カンマ区切り）
excluded_tags="needcheck,maybeuse,willnotuse,foltause,module,gdextension,gdswrapper,csharpwrapper,csharponly,2d,3d,ui,other,animation,audio,navigation,multiplayer,network,shader,xr,physics,mit,gpl,cc0,bsd3,bsd3clause,paid,editoronly,assetlib,notassetlib"

# タグ翻訳ファイルが存在しない場合、新規作成
if [ ! -f "$tag_translation_file" ]; then
    echo "{}" > "$tag_translation_file"
fi

# マージを実行
jq -s '.[0] * .[1]' "$output_file" "$editable_file" > "$merged_file"

# すべてのタグを抽出し、除外リストに含まれないタグをフィルタリング
all_tags=$(jq -r '.[] | .tags[]' "$editable_file" | sort -u | grep -vE "^($(echo $excluded_tags | tr ',' '|'))$")

# マージ結果にタグリストを追加
jq --arg tags "$all_tags" '. + {"tags": ($tags | split("\n") | select(length > 0))}' "$merged_file" > "${merged_file}.tmp" && mv "${merged_file}.tmp" "$merged_file"

echo "マージ結果を $merged_file に保存しました。"

# タグ翻訳ファイルを更新
for tag in $all_tags; do
    if ! jq -e ".\"$tag\"" "$tag_translation_file" > /dev/null 2>&1; then
        jq --arg tag "$tag" '. + {($tag): {"ja": $tag, "ko": $tag, "en": $tag}}' "$tag_translation_file" > "${tag_translation_file}.tmp" && mv "${tag_translation_file}.tmp" "$tag_translation_file"
    fi
done

echo "タグ翻訳ファイル $tag_translation_file を更新しました。"

# タグ翻訳ファイルをコピー
cp "$tag_translation_file" "$tag_translation_file_copy_to"

# マージ後のファイルの更新日時を合わせる
touch -r "$merged_file" "$output_file" "$editable_file" "$tag_translation_file"
echo "マージ後のファイル、出力ファイル、編集用ファイル、タグ翻訳ファイルの更新日時を同期しました。"
