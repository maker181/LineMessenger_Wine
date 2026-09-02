#!/bin/bash

# ==============================================================================
# LINE Native 搬運與簽署分離 + 跨 Prefix 共享 + 正方形 Icon 修復 (v7.2)
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BASE_WINE_DIR="$HOME/Wine"
PRIMARY_LINE_DIR="$BASE_WINE_DIR/LINE"
BOTTLES_BASE="$HOME/.var/app/com.usebottles.bottles/data/bottles"

HAS_ZENITY=false
if command -v zenity &> /dev/null; then
    HAS_ZENITY=true
fi

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}   LINE Native 管理工具 v7.2 (圖示比例修正版)       ${NC}"
echo -e "${BLUE}====================================================${NC}\n"

# ------------------------------------------------------------------------------
# 主選單
# ------------------------------------------------------------------------------
CHOICE=""
if [ "$HAS_ZENITY" = true ]; then
    CHOICE=$(zenity --list --radiolist \
        --title="LINE Native 管理工具" \
        --width=600 --height=300 \
        --column="選擇" --column="選項" --column="動作說明" \
        TRUE "1" "搬運與設定 Prefix (步驟一：複製 Bottle、建立家目錄與貼圖共享連結)" \
        FALSE "2" "執行 DLL 數位簽署 (步驟二：LINE 初始化後，對 Prefix 進行數位簽署)" 2>/dev/null || true)
else
    echo "請選擇要執行的功能："
    echo " [1] 搬運與設定 Prefix (複製 Bottle + 建立資料夾/貼圖連結)"
    echo " [2] 執行 DLL 數位簽署 (讓 LINE 能正常開起)"
    read -p "請輸入選項 [1/2]: " CHOICE
fi

if [ -z "$CHOICE" ]; then
    echo -e "${RED}已取消操作。${NC}"
    exit 0
fi

# ==============================================================================
# 功能 1：搬運與設定 Prefix
# ==============================================================================
if [ "$CHOICE" = "1" ]; then
    echo -e "\n${YELLOW}>>> [功能 1] 搬運與設定 Prefix${NC}"

    SELECTED_BOTTLE=""
    [ "$HAS_ZENITY" = true ] && SELECTED_BOTTLE=$(zenity --file-selection --directory --title="【步驟 1】請選取 Bottle 容器根目錄" --filename="$BOTTLES_BASE/bottles/" 2>/dev/null || true)
    [ -z "$SELECTED_BOTTLE" ] && read -p "請輸入 Bottle 容器路徑: " SELECTED_BOTTLE

    if [ ! -f "$SELECTED_BOTTLE/system.reg" ]; then
        echo -e "${RED}錯誤：不是有效的 Wine Prefix！${NC}"; exit 1
    fi

    WINE_RUNNER_PATH=""
    [ "$HAS_ZENITY" = true ] && WINE_RUNNER_PATH=$(zenity --file-selection --directory --title="【步驟 2】請選取 Wine Runner 資料夾" --filename="$BOTTLES_BASE/runners/" 2>/dev/null || true)
    [ -z "$WINE_RUNNER_PATH" ] && read -p "請輸入 Wine Runner 路徑: " WINE_RUNNER_PATH

    TARGET_NAME="LINE"
    TARGET_DIR="$BASE_WINE_DIR/$TARGET_NAME"
    IS_SECONDARY=false

    if [ -d "$TARGET_DIR" ]; then
        COUNTER=2
        NEW_NAME="LINE_$COUNTER"
        while [ -d "$BASE_WINE_DIR/$NEW_NAME" ]; do
            COUNTER=$((COUNTER + 1))
            NEW_NAME="LINE_$COUNTER"
        done

        MSG="主 Prefix ($TARGET_DIR) 已存在！\n是否建立新建 Prefix：$NEW_NAME ？\n(選擇『否』將覆蓋主 Prefix)"
        if [ "$HAS_ZENITY" = true ]; then
            if zenity --question --title="建立新 Prefix" --text="$MSG" --ok-label="建立 $NEW_NAME" --cancel-label="覆蓋 $TARGET_NAME"; then
                ACTION="rename"
            else
                ACTION="overwrite"
            fi
        else
            read -p "是否建立新建 Prefix $NEW_NAME？ (y: 建立新 Prefix / n: 覆蓋原本): " C_ANS
            case "$C_ANS" in [Yy]*) ACTION="rename" ;; *) ACTION="overwrite" ;; esac
        fi

        if [ "$ACTION" = "rename" ]; then
            TARGET_NAME="$NEW_NAME"
            TARGET_DIR="$BASE_WINE_DIR/$TARGET_NAME"
            IS_SECONDARY=true
        fi
    fi

    echo -e "${YELLOW}正在複製 Prefix 至 $TARGET_DIR ...${NC}"
    mkdir -p "$TARGET_DIR"
    rm -rf "${TARGET_DIR:?}"/*
    cp -a "$SELECTED_BOTTLE"/* "$TARGET_DIR/"

    LAUNCHER_PATH=$(find "$TARGET_DIR/drive_c/users" -type f -name "LineLauncher.exe" 2>/dev/null | head -n 1)
    INTERNAL_USER=$(echo "$LAUNCHER_PATH" | sed -n 's|.*/drive_c/users/\([^/]*\)/.*|\1|p')

    # 建立 Home 軟連結
    echo -e "${YELLOW}正在建立家目錄 (Home) 軟連結...${NC}"
    WINE_USER_DIR="$TARGET_DIR/drive_c/users/$INTERNAL_USER"
    if [ -d "$WINE_USER_DIR" ]; then
        LINUX_DOWNLOADS="$(xdg-user-dir DOWNLOAD 2>/dev/null || echo "$HOME/Downloads")"
        LINUX_DOCUMENTS="$(xdg-user-dir DOCUMENTS 2>/dev/null || echo "$HOME/Documents")"
        LINUX_PICTURES="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
        
        declare -A MAPS=( ["Downloads"]="$LINUX_DOWNLOADS" ["Documents"]="$LINUX_DOCUMENTS" ["Pictures"]="$LINUX_PICTURES" )
        for win_folder in "${!MAPS[@]}"; do
            target_linux_path="${MAPS[$win_folder]}"
            wine_target_path="$WINE_USER_DIR/$win_folder"
            mkdir -p "$target_linux_path"
            rm -rf "$wine_target_path" 2>/dev/null || true
            ln -s "$target_linux_path" "$wine_target_path"
        done
        echo -e "${GREEN}✓ 個人資料夾連結完畢${NC}"
    fi

    # 建立副 Prefix 共享貼圖
    if [ "$IS_SECONDARY" = true ] && [ -d "$PRIMARY_LINE_DIR" ]; then
        echo -e "${YELLOW}正在建立共享貼圖連結...${NC}"
        PRIMARY_DATA_DIR="$PRIMARY_LINE_DIR/drive_c/users/$INTERNAL_USER/AppData/Local/LINE/Data"
        TARGET_DATA_DIR="$TARGET_DIR/drive_c/users/$INTERNAL_USER/AppData/Local/LINE/Data"

        mkdir -p "$PRIMARY_DATA_DIR/Sticker" "$PRIMARY_DATA_DIR/Sticon"
        mkdir -p "$TARGET_DATA_DIR"

        rm -rf "$TARGET_DATA_DIR/Sticker"
        ln -s "$PRIMARY_DATA_DIR/Sticker" "$TARGET_DATA_DIR/Sticker"

        rm -rf "$TARGET_DATA_DIR/Sticon"
        ln -s "$PRIMARY_DATA_DIR/Sticon" "$TARGET_DATA_DIR/Sticon"

        echo -e "${GREEN}✓ Sticker 與 Sticon 均已成功鏈結至第一個 LINE${NC}"
    fi

    # 建立啟動檔與捷徑 (修正 Icon 指向)
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

    # 精準定位正方形的 LineLauncher.png 圖示
    ICON_PATH=""
    if [ -f "$TARGET_DIR/icons/LineLauncher.png" ]; then
        ICON_PATH="$TARGET_DIR/icons/LineLauncher.png"
    elif [ -f "$TARGET_DIR/icons/LINE.png" ]; then
        ICON_PATH="$TARGET_DIR/icons/LINE.png"
    else
        ICON_PATH=$(find "$TARGET_DIR/drive_c/users/$INTERNAL_USER/AppData/Local/LINE" -type f -name "*Launcher*.png" ! -name "*banner*" 2>/dev/null | head -n 1)
    fi
    [ -z "$ICON_PATH" ] && ICON_PATH="line"

    DESKTOP_DIR="$HOME/.local/share/applications"
    DESKTOP_FILE="$DESKTOP_DIR/${TARGET_NAME}-Native.desktop"
    mkdir -p "$DESKTOP_DIR"

    cat << EOF > "$DESKTOP_FILE"
[Desktop Entry]
Name=LINE ($TARGET_NAME)
Exec="$RUN_SCRIPT"
Type=Application
StartupNotify=true
Icon=$ICON_PATH
Categories=Network;InstantMessaging;
EOF

    USER_DESKTOP="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
    if [ -d "$USER_DESKTOP" ]; then
        ON_DESKTOP_FILE="$USER_DESKTOP/LINE-${TARGET_NAME}.desktop"
        cp "$DESKTOP_FILE" "$ON_DESKTOP_FILE"
        chmod +x "$ON_DESKTOP_FILE"
        gio set "$ON_DESKTOP_FILE" metadata::trusted true 2>/dev/null || true
    fi

    echo -e "\n${GREEN}====================================================${NC}"
    echo -e "${GREEN} 步驟一完成！圖示已修正為 $ICON_PATH${NC}"
    echo -e "${GREEN} 請點擊桌面捷徑開啟 LINE，讓 Wine 完成初始化。${NC}"
    echo -e "${GREEN} 關閉 LINE 後，再次執行本腳本選 [2] 進行數位簽署！${NC}"
    echo -e "${GREEN}====================================================${NC}"

# ==============================================================================
# 功能 2：執行 DLL 數位簽署
# ==============================================================================
elif [ "$CHOICE" = "2" ]; then
    echo -e "\n${YELLOW}>>> [功能 2] 執行 DLL 數位簽署${NC}"

    MISSING_DEPS=()
    for cmd in openssl osslsigncode; do
        if ! command -v "$cmd" &> /dev/null; then MISSING_DEPS+=("$cmd"); fi
    done
    if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
        echo -e "${RED}錯誤: 缺少套件 ${MISSING_DEPS[*]}，請先安裝！${NC}"; exit 1
    fi

    TARGET_WIN_DIR=""
    if [ "$HAS_ZENITY" = true ]; then
        TARGET_WIN_DIR=$(zenity --file-selection --directory \
            --title="請選擇要簽署 Prefix 的 windows 資料夾 (例如: ~/Wine/LINE/drive_c/windows)" \
            --filename="$BASE_WINE_DIR/" 2>/dev/null || true)
    else
        read -p "請輸入 Windows 資料夾完整路徑 (如 ~/Wine/LINE/drive_c/windows): " TARGET_WIN_DIR
    fi

    if [ -z "$TARGET_WIN_DIR" ] || [ ! -d "$TARGET_WIN_DIR/system32" ]; then
        echo -e "${RED}錯誤：選取的目錄無效，找不到 system32 資料夾！${NC}"; exit 1
    fi

    echo -e "${GREEN}目標路徑：$TARGET_WIN_DIR${NC}"
    echo -e "${YELLOW}開始產生金鑰並對 DLL 進行簽署...${NC}"

    WORK_DIR="$HOME/.wine_line_fix_cert"
    mkdir -p "$WORK_DIR" && cd "$WORK_DIR"

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
                fi
            done
        fi
    }

    sign_dir "$TARGET_WIN_DIR/system32"
    sign_dir "$TARGET_WIN_DIR/syswow64"

    echo -e "\n${GREEN}====================================================${NC}"
    echo -e "${GREEN} 數位簽署完成！共簽署 $SIGNED_COUNT 個 DLL 檔案。${NC}"
    echo -e "${GREEN} 現在你可以重新啟動 LINE 了！${NC}"
    echo -e "${GREEN}====================================================${NC}"
fi