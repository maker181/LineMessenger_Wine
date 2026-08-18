#!/bin/bash
# ==============================================================================
# LINE on Wine / Bottles 數位簽章自動修復工具
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}    LINE Wine / Bottles 數位簽章自動修復工具       ${NC}"
echo -e "${BLUE}====================================================${NC}\n"

# 1. 檢查必要工具
echo -e "${YELLOW}[1/4] 檢查系統必要依賴工具...${NC}"

MISSING_DEPS=()
for cmd in openssl osslsigncode; do
    if ! command -v "$cmd" &> /dev/null; then
        MISSING_DEPS+=("$cmd")
    fi
done

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo -e "${RED}錯誤: 缺少以下必要工具: ${MISSING_DEPS[*]}${NC}"
    echo -e "請先安裝對應套件，例如："
    echo -e "  Debian/Ubuntu: ${YELLOW}sudo apt install ${MISSING_DEPS[*]}${NC}"
    echo -e "  Fedora:        ${YELLOW}sudo dnf install ${MISSING_DEPS[*]}${NC}"
    echo -e "  Arch Linux:    ${YELLOW}sudo pacman -S ${MISSING_DEPS[*]}${NC}"
    exit 1
fi
echo -e "${GREEN}✓ 必要依賴工具已齊備${NC}\n"

# 2. 詢問 Windows 資料夾路徑
echo -e "${YELLOW}[2/4] 請選擇或輸入 Bottle 的 Windows 資料夾路徑${NC}"
echo -e "提示: 可直接拖曳資料夾至此終端機視窗，或貼上完整路徑\n"

WINDIR=""
if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
    if command -v zenity &> /dev/null; then
        WINDIR=$(zenity --file-selection --directory --title="選擇 Bottle 的 Windows 資料夾" 2>/dev/null || true)
    elif command -v kdialog &> /dev/null; then
        WINDIR=$(kdialog --getexistingdirectory "$HOME" --title "選擇 Bottle 的 Windows 資料夾" 2>/dev/null || true)
    fi
fi

if [ -z "$WINDIR" ]; then
    read -p "請輸入路徑: " WINDIR
fi

# 清理引號與結尾斜線
WINDIR=$(echo "$WINDIR" | tr -d "'" | tr -d '"' | sed 's#/$##')
WINDIR="${WINDIR/#\~/$HOME}"

if [ ! -d "$WINDIR" ]; then
    echo -e "${RED}錯誤: 找不到目錄 '$WINDIR'${NC}"
    exit 1
fi

if [ ! -d "$WINDIR/system32" ]; then
    echo -e "${RED}錯誤: '$WINDIR' 下未找到 'system32' 資料夾，請確認是否為正確的 Windows 目錄！${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 目標路徑確定: $WINDIR${NC}\n"

# 3. 建立自簽憑證
WORK_DIR="$HOME/.wine_line_fix_cert"
echo -e "${YELLOW}[3/4] 產生自簽憑證中 (工作目錄: $WORK_DIR)...${NC}"

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

echo -e "${GREEN}✓ 偽造 Microsoft 憑證建立完成${NC}\n"

# 4. 執行批次簽署
echo -e "${YELLOW}[4/4] 開始對 Wine DLL 檔案進行數位簽署...${NC}"
echo -e "這可能需要幾分鐘時間，請稍候...\n"

SIGNED_COUNT=0
FAIL_COUNT=0

sign_dir() {
    local target_dir="$1"
    if [ -d "$target_dir" ]; then
        for file in "$target_dir"/*.dll; do
            [ -e "$file" ] || continue
            echo -ne "正在簽署: $(basename "$file")\033[0K\r"
            if osslsigncode sign -certs codesign.crt -key codesign.key -in "$file" -out "${file}.signed" > /dev/null 2>&1; then
                mv "${file}.signed" "$file" -f
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
echo -e "${GREEN}    修復完成！${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "成功簽署 DLL 數量: ${GREEN}$SIGNED_COUNT${NC}"
if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "失敗/跳過數量: ${YELLOW}$FAIL_COUNT${NC}"
fi
echo -e "\n現在你可以下載並啟動 LINE 安裝檔 (LineInst.exe) 進行安裝與登入。"