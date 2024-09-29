#!/bin/bash

# 入力ディレクトリと出力ディレクトリを設定
input_directory="/home/folta/Documents/GitHub/folta-blog/work/images"
output_directory="/home/folta/Documents/GitHub/folta-blog/static/images/addon/imagethumbnails"
play_button="/home/folta/Documents/GitHub/folta-blog/static/images/play_button.png"

output_image_directory="/home/folta/Documents/GitHub/folta-blog/static/images/addon/images"

# ディレクトリと再生ボタン画像が存在するか確認
if [ ! -d "$input_directory" ]; then
    echo "エラー: 指定された入力ディレクトリが存在しません。"
    exit 1
fi
if [ ! -d "$output_directory" ]; then
    echo "出力ディレクトリが存在しないため、作成します。"
    mkdir -p "$output_directory"
fi
if [ ! -d "$output_image_directory" ]; then
    echo "出力Imageディレクトリが存在しないため、作成します。"
    mkdir -p "$output_directory"
fi
if [ ! -f "$play_button" ]; then
    echo "エラー: 指定された再生ボタン画像が存在しません。"
    exit 1
fi

# コピーを実行
cp -R "$input_directory"/* "$output_image_directory"/

# 入力ディレクトリ内の全ファイルを処理（ディレクトリは無視）
for file in "$input_directory"/*; do
    # ファイルであることを確認（ディレクトリを無視）
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        extension="${filename##*.}"
        basename="${filename%.*}"
        
        # ファイルタイプを確認
        filetype=$(file -b --mime-type "$file")
        
        # 画像ファイルの処理
        if [[ $filetype == image/* && $filetype != image/gif ]]; then
            if [[ "${extension,,}" == "svg" ]]; then
                # SVGの場合、拡大してから変換
		# SVGの現在のサイズを取得
		size=$(identify -format "%wx%h" "$file")
		width=$(echo $size | cut -d'x' -f1)
		height=$(echo $size | cut -d'x' -f2)

		# スケール比率を計算
		scale_w=$(echo "96 / $width" | bc -l)
		scale_h=$(echo "96 / $height" | bc -l)

		# より小さい方のスケール比率を選択（両辺が96pxを超えるようにするため）
		if (( $(echo "$scale_w > $scale_h" | bc -l) )); then
		    scale=$scale_w
		else
		    scale=$scale_h
		fi

		# スケールを適用して新しいサイズを計算
		new_width=$(echo "$width * $scale" | bc | awk '{print int($1+0.5)}')
		new_height=$(echo "$height * $scale" | bc | awk '{print int($1+0.5)}')

		# ImageMagickを使用してSVGをPNGに変換し、リサイズ
		convert "$file" -resize "${new_width}x${new_height}" "$output_directory/${basename}.jpg"            
            else
                # 通常の画像ファイルの場合
                cp "$file" "$output_directory/${basename}_temp.png"
            
		# アスペクト比を維持しつつ、短辺を96pxに固定
		size=$(identify -format "%wx%h" "$output_directory/${basename}_temp.png")
		width=$(echo $size | cut -d'x' -f1)
		height=$(echo $size | cut -d'x' -f2)

		# 短辺が96pxになるようにリサイズ
		if [ $width -lt $height ]; then
		new_size="96x"
		else
		new_size="x96"
		fi
		convert "$output_directory/${basename}_temp.png" -resize "$new_size" -quality 90 "$output_directory/${basename}.webp"
		
		rm "$output_directory/${basename}_temp.png"

            fi
            
            echo "処理完了 (画像): $filename -> ${basename}.webp"
        # 動画ファイル（gifを含む）の処理
        elif [[ $filetype == video/* || $filetype == image/gif ]]; then
		# 動画のサイズを取得
		video_size=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$file")

		# ffmpegを使用して最初のフレームを抽出し、元のサイズでサムネイルを生成
		ffmpeg -i "$file" -vframes 1 -an -s $video_size -ss 0 "$output_directory/${basename}_temp.png" -y
		# 最初のフレームを抽出してサムネイルを作成
		#ffmpeg -i "$file" -vframes 1 -an -ss 0 "$output_directory/${basename}_temp.png"

		# アスペクト比を維持しつつ、短辺を96pxに固定
		size=$(identify -format "%wx%h" "$output_directory/${basename}_temp.png")
		width=$(echo $size | cut -d'x' -f1)
		height=$(echo $size | cut -d'x' -f2)

		# 短辺が96pxになるようにリサイズ
		if [ $width -lt $height ]; then
			new_size="96x"
		else
			new_size="x96"
		fi
		convert "$output_directory/${basename}_temp.png" -resize "$new_size" "$output_directory/${basename}_temp2.png"

		# 再生ボタンを重ねる
		composite -gravity center "$play_button" "$output_directory/${basename}_temp2.png" -quality 90 "$output_directory/${basename}.webp"

		rm "$output_directory/${basename}_temp.png" "$output_directory/${basename}_temp2.png"
		echo "処理完了 (動画): $filename -> ${basename}.webp"
        else
            echo "スキップ: $file (対応していないファイル形式)"
            continue
        fi
    else
        echo "スキップ: $file (ディレクトリです)"
    fi
done
echo "全ての処理が完了しました。"
