#!/bin/bash

# ==============================================================================
# LINE Native 移行・署名分離 + 複数Prefix共有 + 正方形アイコン修復 (v7.2)
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
echo -e "${BLUE}   LINE Native 管理ツール v7.2 (アイコン比率修正版) ${NC}"
echo -e "${BLUE}====================================================${NC}\n"

# ------------------------------------------------------------------------------
# メインメニュー
# ------------------------------------------------------------------------------
CHOICE=""
if [ "$HAS_ZENITY" = true ]; then
    CHOICE=$(zenity --list --radiolist \
        --title="LINE Native 管理ツール" \
        --width=640 --height=300 \
        --column="選択" --column="番号" --column="処理内容" \
        TRUE "1" "Prefix の移行と設定 (手順1: Bottleのコピー、ホーム/スタンプ共有リンク作成)" \
        FALSE "2" "DLL デジタル署名の実行 (手順2: LINE 初期化後、Prefix の DLL を署名)" 2>/dev/null || true)
else
    echo "実行する機能を選択してください："
    echo " [1] Prefix の移行と設定 (Bottle のコピー + フォルダ/スタンプのリンク作成)"
    echo " [2] DLL デジタル署名の実行 (LINE を正常起動させるための署名)"
    read -p "番号を入力してください [1/2]: " CHOICE
fi

if [ -z "$CHOICE" ]; then
    echo -e "${RED}操作がキャンセルされました。${NC}"
    exit 0
fi

# ==============================================================================
# 機能 1：Prefix の移行と設定
# ==============================================================================
if [ "$CHOICE" = "1" ]; then
    echo -e "\n${YELLOW}>>> [機能 1] Prefix の移行と設定${NC}"

    SELECTED_BOTTLE=""
    [ "$HAS_ZENITY" = true ] && SELECTED_BOTTLE=$(zenity --file-selection --directory --title="【ステップ 1】Bottle コンテナのルートフォルダを選択してください" --filename="$BOTTLES_BASE/bottles/" 2>/dev/null || true)
    [ -z "$SELECTED_BOTTLE" ] && read -p "Bottle コンテナのパスを入力してください: " SELECTED_BOTTLE

    if [ ! -f "$SELECTED_BOTTLE/system.reg" ]; then
        echo -e "${RED}エラー: 有効な Wine Prefix ではありません！${NC}"; exit 1
    fi

    WINE_RUNNER_PATH=""
    [ "$HAS_ZENITY" = true ] && WINE_RUNNER_PATH=$(zenity --file-selection --directory --title="【ステップ 2】Wine Runner フォルダを選択してください" --filename="$BOTTLES_BASE/runners/" 2>/dev/null || true)
    [ -z "$WINE_RUNNER_PATH" ] && read -p "Wine Runner のパスを入力してください: " WINE_RUNNER_PATH

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

        MSG="メイン Prefix ($TARGET_DIR) は既に存在します！\n新しい Prefix: $NEW_NAME を作成しますか？\n(「いいえ」を選ぶと既存のメイン Prefix を上書きします)"
        if [ "$HAS_ZENITY" = true ]; then
            if zenity --question --title="新規 Prefix の作成" --text="$MSG" --ok-label="$NEW_NAME を新規作成" --cancel-label="$TARGET_NAME を上書き"; then
                ACTION="rename"
            else
                ACTION="overwrite"
            fi
        else
            read -p "新規 Prefix $NEW_NAME を作成しますか？ (y: 新規作成 / n: 上書き): " C_ANS
            case "$C_ANS" in [Yy]*) ACTION="rename" ;; *) ACTION="overwrite" ;; esac
        fi

        if [ "$ACTION" = "rename" ]; then
            TARGET_NAME="$NEW_NAME"
            TARGET_DIR="$BASE_WINE_DIR/$TARGET_NAME"
            IS_SECONDARY=true
        fi
    fi

    echo -e "${YELLOW}Prefix を $TARGET_DIR にコピーしています...${NC}"
    mkdir -p "$TARGET_DIR"
    rm -rf "${TARGET_DIR:?}"/*
    cp -a "$SELECTED_BOTTLE"/* "$TARGET_DIR/"

    LAUNCHER_PATH=$(find "$TARGET_DIR/drive_c/users" -type f -name "LineLauncher.exe" 2>/dev/null | head -n 1)
    INTERNAL_USER=$(echo "$LAUNCHER_PATH" | sed -n 's|.*/drive_c/users/\([^/]*\)/.*|\1|p')

    # ホームフォルダ (Home) のシンボリックリンク作成
    echo -e "${YELLOW}ユーザーフォルダ (Home) のシンボリックリンクを作成中...${NC}"
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
        echo -e "${GREEN}✓ 個人フォルダのリンクが完了しました${NC}"
    fi

    # サブ Prefix 用のスタンプ共有リンク作成
    if [ "$IS_SECONDARY" = true ] && [ -d "$PRIMARY_LINE_DIR" ]; then
        echo -e "${YELLOW}スタンプ共有リンクを作成中...${NC}"
        PRIMARY_DATA_DIR="$PRIMARY_LINE_DIR/drive_c/users/$INTERNAL_USER/AppData/Local/LINE/Data"
        TARGET_DATA_DIR="$TARGET_DIR/drive_c/users/$INTERNAL_USER/AppData/Local/LINE/Data"

        mkdir -p "$PRIMARY_DATA_DIR/Sticker" "$PRIMARY_DATA_DIR/Sticon"
        mkdir -p "$TARGET_DATA_DIR"

        rm -rf "$TARGET_DATA_DIR/Sticker"
        ln -s "$PRIMARY_DATA_DIR/Sticker" "$TARGET_DATA_DIR/Sticker"

        rm -rf "$TARGET_DATA_DIR/Sticon"
        ln -s "$PRIMARY_DATA_DIR/Sticon" "$TARGET_DATA_DIR/Sticon"

        echo -e "${GREEN}✓ Sticker (スタンプ) と Sticon (絵文字) の共有リンクを完了しました${NC}"
    fi

    # 起動スクリプトとショートカットの作成 (正方形アイコン対応)
    RUN_SCRIPT="$TARGET_DIR/run-line.sh"
    cat << EOF > "$RUN_SCRIPT"
#!/bin/bash
export WINEPREFIX="$TARGET_DIR"
export XMODIFIERS="@im=fcitx"
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export SDL_IM_MODULE=fcitx
export INPUT_METHOD=fcitx
export LC_ALL=ja_JP.UTF-8

"$WINE_RUNNER_PATH/bin/wine" "$LAUNCHER_PATH" "\$@"
EOF
    chmod +x "$RUN_SCRIPT"

    # 正方形の LineLauncher.png アイコンを特定
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
    echo -e "${GREEN} 手順 1 が完了しました！アイコン: $ICON_PATH${NC}"
    echo -e "${GREEN} デスクトップのショートカットから一度 LINE を起動し、${NC}"
    echo -e "${GREEN} Wine の初期設定を完了させてください。${NC}"
    echo -e "${GREEN} LINE を閉じた後、再度本スクリプトで [2] を実行してください！${NC}"
    echo -e "${GREEN}====================================================${NC}"

# ==============================================================================
# 機能 2：DLL デジタル署名の実行
# ==============================================================================
elif [ "$CHOICE" = "2" ]; then
    echo -e "\n${YELLOW}>>> [機能 2] DLL デジタル署名の実行${NC}"

    MISSING_DEPS=()
    for cmd in openssl osslsigncode; do
        if ! command -v "$cmd" &> /dev/null; then MISSING_DEPS+=("$cmd"); fi
    done
    if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
        echo -e "${RED}エラー: 必要なツール ${MISSING_DEPS[*]} が見つかりません。先にインストールしてください！${NC}"; exit 1
    fi

    TARGET_WIN_DIR=""
    if [ "$HAS_ZENITY" = true ]; then
        TARGET_WIN_DIR=$(zenity --file-selection --directory \
            --title="署名対象の Prefix 内 windows フォルダを選択してください (例: ~/Wine/LINE/drive_c/windows)" \
            --filename="$BASE_WINE_DIR/" 2>/dev/null || true)
    else
        read -p "Windows フォルダのフルパスを入力してください (例: ~/Wine/LINE/drive_c/windows): " TARGET_WIN_DIR
    fi

    if [ -z "$TARGET_WIN_DIR" ] || [ ! -d "$TARGET_WIN_DIR/system32" ]; then
        echo -e "${RED}エラー: 指定されたディレクトリが無効です (system32 が見つかりません)！${NC}"; exit 1
    fi

    echo -e "${GREEN}対象パス: $TARGET_WIN_DIR${NC}"
    echo -e "${YELLOW}証明書を生成し、DLL のデジタル署名を開始します...${NC}"

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
                echo -ne "署名中: $(basename "$file")\033[0K\r"
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
    echo -e "${GREEN} デジタル署名が完了しました！ 合計 $SIGNED_COUNT 個の DLL を署名しました。${NC}"
    echo -e "${GREEN} これで LINE を正常に起動できます！${NC}"
    echo -e "${GREEN}====================================================${NC}"
fi