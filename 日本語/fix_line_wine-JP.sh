#!/bin/bash
# ==============================================================================
# LINE on Wine / Bottles デジタル署名自動修復スクリプト
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}   LINE Wine / Bottles デジタル署名自動修復ツール   ${NC}"
echo -e "${BLUE}====================================================${NC}\n"

# 1. 依存関係チェック
echo -e "${YELLOW}[1/4] 必要なツールの確認中...${NC}"

MISSING_DEPS=()
for cmd in openssl osslsigncode; do
    if ! command -v "$cmd" &> /dev/null; then
        MISSING_DEPS+=("$cmd")
    fi
done

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo -e "${RED}エラー: 必要なツールが見つかりません: ${MISSING_DEPS[*]}${NC}"
    echo -e "以下のコマンドでインストールしてください："
    echo -e "  Arch Linux / Steam Deck: ${YELLOW}sudo pacman -S ${MISSING_DEPS[*]}${NC}"
    echo -e "  Debian / Ubuntu:         ${YELLOW}sudo apt install ${MISSING_DEPS[*]}${NC}"
    echo -e "  Fedora:                  ${YELLOW}sudo dnf install ${MISSING_DEPS[*]}${NC}"
    exit 1
fi
echo -e "${GREEN}✓ 依存関係チェック完了${NC}\n"

# 2. Windows フォルダの指定
echo -e "${YELLOW}[2/4] Bottle/Prefix の Windows フォルダを選択してください${NC}"
echo -e "ヒント: フォルダをこのターミナルにドラッグ＆ドロップするか、フルパスを入力してください。\n"

WINDIR=""
if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
    if command -v zenity &> /dev/null; then
        WINDIR=$(zenity --file-selection --directory --title="Bottle の Windows フォルダを選択" 2>/dev/null || true)
    elif command -v kdialog &> /dev/null; then
        WINDIR=$(kdialog --getexistingdirectory "$HOME" --title "Bottle の Windows フォルダを選択" 2>/dev/null || true)
    fi
fi

if [ -z "$WINDIR" ]; then
    read -p "パスを入力: " WINDIR
fi

WINDIR=$(echo "$WINDIR" | tr -d "'" | tr -d '"' | sed 's#/$##')
WINDIR="${WINDIR/#\~/$HOME}"

if [ ! -d "$WINDIR" ]; then
    echo -e "${RED}エラー: ディレクトリが見つかりません '$WINDIR'${NC}"
    exit 1
fi

if [ ! -d "$WINDIR/system32" ]; then
    echo -e "${RED}エラー: '$WINDIR' 内に 'system32' が見つかりません。正しい Windows ディレクトリか確認してください！${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 対象パス確認完了: $WINDIR${NC}\n"

# 3. 自己署名証明書の生成
WORK_DIR="$HOME/.wine_line_fix_cert"
echo -e "${YELLOW}[3/4] 自己署名証明書を生成中 (作業場所: $WORK_DIR)...${NC}"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

cat << EOF > codesign.conf
[req]
prompt = no
default_md = sha256
default_bits = 2048
distinguished_name = dn
x509_extensions = v3_req

[dn]
C = US
ST = Washington
L = Redmond
O = Microsoft Corporation
CN = Microsoft Windows

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = microsoft.com
EOF

openssl req -x509 -new -nodes -sha256 -utf8 -days 3650 -newkey rsa:2048 \
  -keyout codesign.key -out codesign.crt -config codesign.conf > /dev/null 2>&1

echo -e "${GREEN}✓ 署名用証明書の生成が完了しました${NC}\n"

# 4. DLL 署名処理
echo -e "${YELLOW}[4/4] Wine DLL ファイルのデジタル署名を開始します...${NC}"
echo -e "処理には数分かかる場合があります。しばらくお待ちください...\n"

SIGNED_COUNT=0
FAIL_COUNT=0

sign_dir() {
    local target_dir="$1"
    if [ -d "$target_dir" ]; then
        for file in "$target_dir"/*.dll; do
            [ -e "$file" ] || continue
            echo -ne "署名中: $(basename "$file")\033[0K\r"
            if osslsigncode sign -h sha256 -certs codesign.crt -key codesign.key -in "$file" -out "${file}.signed" > /dev/null 2>&1; then
                chmod +w "$file" 2>/dev/null || true
                rm -f "$file"
                mv "${file}.signed" "$file"
                SIGNED_COUNT=$((SIGNED_COUNT + 1))
            else
                rm -f "${file}.signed"
                FAIL_COUNT=$((FAIL_COUNT + 1))
            fi
        done
    fi
}

sign_dir "$WINDIR/system32"
sign_dir "$WINDIR/syswow64"

echo -e "\n\n${GREEN}====================================================${NC}"
echo -e "${GREEN}    修復が完了しました！${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "署名成功 DLL 数: ${GREEN}$SIGNED_COUNT${NC}"
if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "失敗/スキップ数: ${YELLOW}$FAIL_COUNT${NC}"
fi
echo -e "\nこれで LINE インストーラー (LineInst.exe) の起動・ログインが可能になります。"