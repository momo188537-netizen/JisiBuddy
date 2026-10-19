#!/bin/sh
# 用法：scripts/import-jisi.sh 鸡丝抠图.png
# 用户提供的抠图与原图左右镜像，这里水平翻转回来，并缩到最长边 512px（锁屏 Widget 有内存上限）。
set -e
[ -f "$1" ] || { echo "用法: $0 <鸡丝抠图.png>"; exit 1; }
OUT="$(dirname "$0")/../JisiKit/Sources/JisiKit/Resources/JisiFace.png"
sips -s format png -f horizontal -Z 512 "$1" --out "$OUT" >/dev/null
echo "已导入到 $OUT"
MONO="$(dirname "$0")/../JisiKit/Sources/JisiKit/Resources/JisiFaceMono.png"
swift "$(dirname "$0")/mono-face.swift" "$OUT" "$MONO" 144
echo "已生成锁屏单色头像 $MONO"
