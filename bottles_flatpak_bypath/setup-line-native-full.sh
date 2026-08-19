#!/bin/bash

# ==============================================================================
# LINE Native 搬運 + DLL 數位簽署 + 桌面捷徑工具 (v4.2 - 自訂 Windows 資料夾)
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BASE_WINE_DIR="$HOME/Wine"
BOTTLES_BASE="$HOME/.var/app/com.usebottles.bottles/data/bottles"

HAS_ZENITY=false
if command -v zenity &> /dev/null; then
    HAS_ZENITY=true
fi

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}   LINE Native 搬運 + DLL 數位簽署 + 捷徑全自動工具 ${NC}"
echo -e "${BLUE}====================================================${NC}\n"

# ------------------------------------------------------------------------------
# 步驟 0: 前置檢查依賴
# ------------------------------------------------------------------------------
echo -e "${YELLOW}[0/6] 檢查系統必要工具 (openssl, osslsigncode)...${NC}"

MISSING_DEPS=()
for cmd in openssl osslsigncode; do
    if ! command -v "$cmd" &> /dev/null; then
        MISSING_DEPS+=("$cmd")
    fi
done

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    MSG="【缺少的必要工具】: ${MISSING_DEPS[*]}\n\n請先開啟終端機安裝對應套件後再執行此腳本！"
    echo -e "${RED}錯誤: 缺少以下必要工具: ${MISSING_DEPS[*]}${NC}"
    if [ "$HAS_ZENITY" = true ]; then
        zenity --error --title="缺少必要工具" --text="$MSG" --width=450
    fi
    exit 1
fi

echo -e "${GREEN}✓ 必要工具已齊備${NC}\n"

# ------------------------------------------------------------------------------
# 步驟 1: 選取 Bottles 容器
# ------------------------------------------------------------------------------
echo -e "${YELLOW}[1/6] 自動搜尋與選取 Bottles 容器...${NC}"
FOUND_BOTTLES=()
if [ -d "$BOTTLES_BASE/bottles" ]; then
    while IFS= read -r b_dir; do
        if [ -d "$b_dir/drive_c/users" ] && find "$b_dir/drive_c/users" -type d -path "*/AppData/Local/LINE" | grep -q .; then
            FOUND_BOTTLES+=("$b_dir")
        fi
    done < <(find "$BOTTLES_BASE/bottles" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
fi

SELECTED_BOTTLE=""
if [ ${#FOUND_BOTTLES[@]} -gt 0 ]; then
    if [ "$HAS_ZENITY" = true ]; then
        ZENITY_ARGS=(--list --radiolist --title="選擇 LINE Bottle 容器" --text="請選擇含有 LINE 的 Bottles 容器：" --column="選擇" --column="Bottle 路徑")
        for i in "${!FOUND_BOTTLES[@]}"; do
            [ $i -eq 0 ] && ZENITY_ARGS+=(TRUE "${FOUND_BOTTLES[$i]}") || ZENITY_ARGS+=(FALSE "${FOUND_BOTTLES[$i]}")
        done
        SELECTED_BOTTLE=$(zenity "${ZENITY_ARGS[@]}")
    else
        for i in "${!FOUND_BOTTLES[@]}"; do echo " [$i] ${FOUND_BOTTLES[$i]}"; done
        read -p "請選擇編號: " INDEX
        SELECTED_BOTTLE="${FOUND_BOTTLES[$INDEX]}"
    fi
fi

if [ -z "$SELECTED_BOTTLE" ]; then
    if [ "$HAS_ZENITY" = true ]; then
        SELECTED_BOTTLE=$(zenity --file-selection --directory --title="請選取 Bottles 容器根目錄" --filename="$BOTTLES_BASE/bottles/")
    else
        read -p "請輸入 Bottle 容器完整路徑: " SELECTED_BOTTLE
    fi
fi

if [ -z "$SELECTED_BOTTLE" ] || [ ! -f "$SELECTED_BOTTLE/system.reg" ]; then
    echo -e "${RED}錯誤：選取的目錄不是有效的 Wine Prefix！${NC}"
    exit 1
fi

# ------------------------------------------------------------------------------
# 步驟 2: 選取 Wine Runner
# ------------------------------------------------------------------------------
echo -e "${YELLOW}[2/6] 選取 Wine Runner...${NC}"
WINE_RUNNER_PATH=""
FOUND_RUNNERS=()
if [ -d "$BOTTLES_BASE/runners" ]; then
    while IFS= read -r runner; do
        FOUND_RUNNERS+=("$runner")
    done < <(find "$BOTTLES_BASE/runners" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
fi

if [ ${#FOUND_RUNNERS[@]} -gt 0 ]; then
    if [ "$HAS_ZENITY" = true ]; then
        ZENITY_ARGS=(--list --radiolist --title="選擇 Wine Runner" --text="請選擇 Wine Runner：" --column="選擇" --column="Runner 路徑")
        for i in "${!FOUND_RUNNERS[@]}"; do
            [ $i -eq 0 ] && ZENITY_ARGS+=(TRUE "${FOUND_RUNNERS[$i]}") || ZENITY_ARGS+=(FALSE "${FOUND_RUNNERS[$i]}")
        done
        WINE_RUNNER_PATH=$(zenity "${ZENITY_ARGS[@]}")
    else
        for i in "${!FOUND_RUNNERS[@]}"; do echo " [$i] ${FOUND_RUNNERS[$i]}"; done
        read -p "請選擇編號: " INDEX
        WINE_RUNNER_PATH="${FOUND_RUNNERS[$INDEX]}"
    fi
fi

if [ -z "$WINE_RUNNER_PATH" ]; then
    if [ "$HAS_ZENITY" = true ]; then
        WINE_RUNNER_PATH=$(zenity --file-selection --directory --title="請選取 Wine Runner 資料夾" --filename="$BOTTLES_BASE/runners/")
    else
        read -p "請輸入 Wine Runner 資料夾完整路徑: " WINE_RUNNER_PATH
    fi
fi

# ------------------------------------------------------------------------------
# 步驟 3: Prefix 複製
# ------------------------------------------------------------------------------
TARGET_NAME="LINE"
TARGET_DIR="$BASE_WINE_DIR/$TARGET_NAME"

if [ -d "$TARGET_DIR" ]; then
    COUNTER=2
    NEW_NAME="LINE_$COUNTER"
    while [ -d "$BASE_WINE_DIR/$NEW_NAME" ]; do
        COUNTER=$((COUNTER + 1))
        NEW_NAME="LINE_$COUNTER"
    done

    MSG="目標目錄 $TARGET_DIR 已存在！\n是否要【覆蓋】資料？(選『否』將自動建立為 $NEW_NAME)"
    if [ "$HAS_ZENITY" = true ]; then
        if zenity --question --title="衝突提醒" --text="$MSG" --ok-label="覆蓋" --cancel-label="新建為 $NEW_NAME"; then
            ACTION="overwrite"
        else
            ACTION="rename"
        fi
    else
        read -p "是否覆蓋原有資料？(y: 覆蓋 / n: 建立為 $NEW_NAME): " CHOICE
        case "$CHOICE" in [Yy]*) ACTION="overwrite" ;; *) ACTION="rename" ;; esac
    fi

    if [ "$ACTION" = "rename" ]; then
        TARGET_NAME="$NEW_NAME"
        TARGET_DIR="$BASE_WINE_DIR/$TARGET_NAME"
    fi
fi

echo -e "\n${YELLOW}[3/6] 複製 Prefix 環境至：$TARGET_DIR ...${NC}"
mkdir -p "$TARGET_DIR"
rm -rf "${TARGET_DIR:?}"/*
cp -a "$SELECTED_BOTTLE"/* "$TARGET_DIR/"

LAUNCHER_PATH=$(find "$TARGET_DIR/drive_c/users" -type f -name "LineLauncher.exe" 2>/dev/null | head -n 1)
if [ -z "$LAUNCHER_PATH" ]; then
    echo -e "${RED}錯誤：複製後找不到 LineLauncher.exe！${NC}"
    exit 1
fi

# ------------------------------------------------------------------------------
# 步驟 4: 選取/確認要進行數位簽署的 Windows 資料夾
# ------------------------------------------------------------------------------
DEFAULT_WINDIR="$TARGET_DIR/drive_c/windows"
echo -e "\n${YELLOW}[4/6] 請選擇要簽署的 Windows 資料夾...${NC}"

if [ "$HAS_ZENITY" = true ]; then
    WINDIR_PATH=$(zenity --file-selection --directory \
        --title="【步驟 4】請選擇要簽署的 Windows 資料夾 (點選到 windows 這一層)" \
        --filename="$DEFAULT_WINDIR/")
else
    echo -e "預設路徑: $DEFAULT_WINDIR"
    read -p "請按 Enter 確認預設路徑，或輸入自訂 Windows 資料夾路徑: " INPUT_WINDIR
    if [ -n "$INPUT_WINDIR" ]; then
        WINDIR_PATH="$INPUT_WINDIR"
    else
        WINDIR_PATH="$DEFAULT_WINDIR"
    fi
fi

if [ -z "$WINDIR_PATH" ] || [ ! -d "$WINDIR_PATH/system32" ]; then
    echo -e "${RED}錯誤：選取的目錄無效，或找不到 system32 資料夾！${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 確定簽署目標資料夾：$WINDIR_PATH${NC}"

# ------------------------------------------------------------------------------
# 步驟 5: 偽造 Microsoft 憑證與批次 DLL 簽署
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[5/6] 開始對 DLL 進行偽造 Microsoft 數位簽署...${NC}"
WORK_DIR="$HOME/.wine_line_fix_cert"
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

SIGNED_COUNT=0
FAIL_COUNT=0

sign_dir() {
    local target_dir="$1"
    if [ -d "$target_dir" ]; then
        for file in "$target_dir"/*.dll; do
            [ -e "$file" ] || continue
            echo -ne "正在簽署: $(basename "$file")\033[0K\r"
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

sign_dir "$WINDIR_PATH/system32"
sign_dir "$WINDIR_PATH/syswow64"

echo -e "\n${GREEN}✓ DLL 數位簽署完成！成功簽署 $SIGNED_COUNT 個檔案 (失敗/跳過: $FAIL_COUNT)。${NC}"

# ------------------------------------------------------------------------------
# 步驟 6: 建立 run-line.sh 與 桌面雙擊捷徑
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[6/6] 建立啟動腳本與桌面捷徑...${NC}"
RUN_SCRIPT="$TARGET_DIR/run-line.sh"

cat << EOF > "$RUN_SCRIPT"
#!/bin/bash
export WINEPREFIX="$TARGET_DIR"
export XMODIFIERS="@im=fcitx"
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export SDL_IM_MODULE=fcitx
export INPUT_METHOD=fcitx
export LC_ALL=zh_TW.UTF-8

"$WINE_RUNNER_PATH/bin/wine" "$LAUNCHER_PATH" "\$@"
EOF

chmod +x "$RUN_SCRIPT"

# 1. 選單捷徑
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/${TARGET_NAME}-Native.desktop"
mkdir -p "$DESKTOP_DIR"

cat << EOF > "$DESKTOP_FILE"
[Desktop Entry]
Name=LINE ($TARGET_NAME)
Exec="$RUN_SCRIPT"
Type=Application
StartupNotify=true
Icon=196C_LineLauncher.0
Categories=Network;InstantMessaging;
EOF

if command -v update-desktop-database &> /dev/null; then
    update-desktop-database "$DESKTOP_DIR"
fi

# 2. 桌面雙擊捷徑
USER_DESKTOP="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
if [ -d "$USER_DESKTOP" ]; then
    ON_DESKTOP_FILE="$USER_DESKTOP/LINE.desktop"
    cp "$DESKTOP_FILE" "$ON_DESKTOP_FILE"
    chmod +x "$ON_DESKTOP_FILE"
    gio set "$ON_DESKTOP_FILE" metadata::trusted true 2>/dev/null || true
    echo -e "${GREEN}✓ 桌面雙擊捷徑已建立：$ON_DESKTOP_FILE${NC}"
fi

echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}    全部修復並建立完成！${NC}"
echo -e "${GREEN}====================================================${NC}"