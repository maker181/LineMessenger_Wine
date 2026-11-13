#!/bin/bash

# ==============================================================================
# LINE Zen Mode — 介面淨化與狀態還原管理工具 (Wine / Flatpak Bottles 通用)
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

BASE_WINE_DIR="$HOME/Wine"
BOTTLES_BASE="$HOME/.var/app/com.usebottles.bottles/data/bottles/bottles"

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}     LINE Zen Mode — 介面淨化與還原管理工具         ${NC}"
echo -e "${BLUE}====================================================${NC}\n"

# ------------------------------------------------------------------------------
# 1. 自動偵測本機 Wine 與 Flatpak Bottles 內的 LINE 環境
# ------------------------------------------------------------------------------
echo -e "${YELLOW}[1/3] 正在掃描本機 Wine 與 Flatpak Bottles 中的 LINE 環境...${NC}"

declare -a LINE_DATA_PATHS
declare -a LINE_LABELS

scan_prefix_dir() {
    local search_root="$1"
    local source_tag="$2"

    [ -d "$search_root" ] || return 0

    for prefix in "$search_root"/*; do
        [ -d "$prefix" ] || continue
        local prefix_name
        prefix_name=$(basename "$prefix")

        # 尋找 drive_c/users/<使用者>/AppData/Local/LINE
        if [ -d "$prefix/drive_c/users" ]; then
            for user_dir in "$prefix/drive_c/users"/*; do
                [ -d "$user_dir" ] || continue
                local u_name
                u_name=$(basename "$user_dir")
                # 排除系統預設目錄
                [[ "$u_name" == "Public" || "$u_name" == "Default" || "$u_name" == "Default User" || "$u_name" == "All Users" ]] && continue

                local line_app_data="$user_dir/AppData/Local/LINE"
                if [ -d "$line_app_data" ]; then
                    LINE_DATA_PATHS+=("$line_app_data")
                    LINE_LABELS+=("[$source_tag] $prefix_name (使用者: $u_name)")
                fi
            done
        fi
    done
}

scan_prefix_dir "$BASE_WINE_DIR" "本機 Wine"
scan_prefix_dir "$BOTTLES_BASE" "Flatpak Bottles"

TARGET_LINE_DIR=""
TARGET_LABEL=""

if [ ${#LINE_DATA_PATHS[@]} -eq 0 ]; then
    echo -e "${YELLOW}未自動偵測到預設路徑下的 LINE 資料夾。${NC}"
    read -p "請手動輸入 Prefix 根目錄路徑 (例如 ~/Wine/LINE): " MANUAL_PREFIX
    MANUAL_PREFIX="${MANUAL_PREFIX/#\~/$HOME}"
    FOUND_LINE=$(find "$MANUAL_PREFIX/drive_c/users" -maxdepth 4 -type d -name "LINE" 2>/dev/null | grep "AppData/Local/LINE" | head -n 1)
    if [ -z "$FOUND_LINE" ] || [ ! -d "$FOUND_LINE" ]; then
        echo -e "${RED}錯誤：在該路徑下找不到 AppData/Local/LINE 資料夾！${NC}"
        exit 1
    fi
    TARGET_LINE_DIR="$FOUND_LINE"
    TARGET_LABEL="[手動指定] $MANUAL_PREFIX"
else
    echo -e "${GREEN}✓ 共偵測到 ${#LINE_DATA_PATHS[@]} 個 LINE 環境：${NC}\n"
    for i in "${!LINE_LABELS[@]}"; do
        idx=$((i + 1))
        echo -e "  ${CYAN}[$idx]${NC} ${LINE_LABELS[$i]}"
        echo -e "      路徑: ${LINE_DATA_PATHS[$i]}"
    done
    echo ""

    if [ ${#LINE_DATA_PATHS[@]} -eq 1 ]; then
        TARGET_LINE_DIR="${LINE_DATA_PATHS[0]}"
        TARGET_LABEL="${LINE_LABELS[0]}"
        echo -e "自動選取唯一環境：${GREEN}$TARGET_LABEL${NC}\n"
    else
        while true; do
            read -p "請輸入要操作的環境編號 [1-${#LINE_DATA_PATHS[@]}]: " ENV_IDX
            if [[ "$ENV_IDX" =~ ^[0-9]+$ ]] && [ "$ENV_IDX" -ge 1 ] && [ "$ENV_IDX" -le ${#LINE_DATA_PATHS[@]} ]; then
                TARGET_LINE_DIR="${LINE_DATA_PATHS[$((ENV_IDX - 1))]}"
                TARGET_LABEL="${LINE_LABELS[$((ENV_IDX - 1))]}"
                break
            else
                echo -e "${RED}輸入無效，請輸入 1 到 ${#LINE_DATA_PATHS[@]} 之間的數字。${NC}"
            fi
        done
        echo -e "\n已選擇目標：${GREEN}$TARGET_LABEL${NC}\n"
    fi
fi

# ------------------------------------------------------------------------------
# 2. 選擇操作模式 (1 / 2 / 3)
# ------------------------------------------------------------------------------
echo -e "${YELLOW}[2/3] 請選擇要執行的模式：${NC}"
echo -e "  ${GREEN}[1]${NC} 開啟 Zen 純淨模式 (清空並鎖定推廣橫幅快取，完整保留頭像與聊天縮圖)"
echo -e "  ${YELLOW}[2]${NC} 關閉 Zen 純淨模式 (解除 chattr +i 結界並還原預設讀寫狀態)"
echo -e "  ${CYAN}[3]${NC} 緊急修復頭像顯示 (若先前誤鎖整個 Cache 資料夾導致頭像消失，用此項全數解鎖)"
echo ""
read -p "請輸入選項 [1/2/3]: " ACTION

if [[ ! "$ACTION" =~ ^[123]$ ]]; then
    echo -e "${RED}無效的選項，已取消操作。${NC}"
    exit 0
fi

# 檢查是否正在執行 LINE
if pgrep -f "LINE.exe" > /dev/null 2>&1; then
    echo -e "\n${YELLOW}⚠ 警告：偵測到 LINE 目前正在背景執行！${NC}"
    echo -e "建議先完全關閉 LINE 再調整狀態，以免鎖定失敗。"
    read -p "是否仍要繼續執行？(y/N): " CONT
    [[ ! "$CONT" =~ ^[Yy]$ ]] && exit 0
fi

# ------------------------------------------------------------------------------
# 3. 執行對應動作
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[3/3] 正在施放設定 (部分指令需要 sudo 權限以設定/解除 chattr +i)...${NC}\n"

DATA_AD_DIR="$TARGET_LINE_DIR/Data/advertisement"
CACHE_DIR="$TARGET_LINE_DIR/Cache"

case "$ACTION" in
    1)
        echo -e ">>> 步驟 A：淨化並鎖定 Data/advertisement 排程設定..."
        mkdir -p "$DATA_AD_DIR"
        sudo chattr -R -i "$DATA_AD_DIR" 2>/dev/null || true
        chmod -R 775 "$DATA_AD_DIR" 2>/dev/null || true

        find "$DATA_AD_DIR" -type f -name "advertisement*.dat" -exec truncate -s 0 {} + 2>/dev/null || true
        find "$DATA_AD_DIR" -type f -name "advertisement*.dat" -exec chmod 444 {} + 2>/dev/null || true
        find "$DATA_AD_DIR" -type d -exec chmod 555 {} + 2>/dev/null || true
        sudo chattr -R +i "$DATA_AD_DIR"
        echo -e "${GREEN}✓ Data/advertisement 已進入純淨鎖定狀態${NC}"

        echo -e ">>> 步驟 B：精準淨化 Cache/<帳號亂數>/e 橫幅快取..."
        E_COUNT=0
        if [ -d "$CACHE_DIR" ]; then
            for acc_dir in "$CACHE_DIR"/*; do
                [ -d "$acc_dir" ] || continue
                target_e="$acc_dir/e"
                mkdir -p "$target_e"
                sudo chattr -R -i "$target_e" 2>/dev/null || true
                chmod -R 775 "$target_e" 2>/dev/null || true
                rm -rf "${target_e:?}"/*
                chmod 555 "$target_e"
                sudo chattr -R +i "$target_e"
                E_COUNT=$((E_COUNT + 1))
            done
        fi
        echo -e "${GREEN}✓ 已淨化 $E_COUNT 個帳號的橫幅快取（頭像與聊天縮圖已完整保留）${NC}"
        ;;

    2)
        echo -e ">>> 步驟 A：解除 Data/advertisement 鎖定..."
        if [ -d "$DATA_AD_DIR" ]; then
            sudo chattr -R -i "$DATA_AD_DIR" 2>/dev/null || true
            chmod -R 775 "$DATA_AD_DIR"
            echo -e "${GREEN}✓ Data/advertisement 已恢復預設讀寫${NC}"
        else
            echo -e "${YELLOW}- 找不到 Data/advertisement，跳過${NC}"
        fi

        echo -e ">>> 步驟 B：解除 Cache/<帳號亂數>/e 鎖定..."
        if [ -d "$CACHE_DIR" ]; then
            for acc_dir in "$CACHE_DIR"/*; do
                [ -d "$acc_dir" ] || continue
                target_e="$acc_dir/e"
                if [ -e "$target_e" ]; then
                    sudo chattr -R -i "$target_e" 2>/dev/null || true
                    chmod -R 775 "$target_e"
                fi
            done
            echo -e "${GREEN}✓ Cache/*/e 已恢復預設讀寫${NC}"
        fi
        ;;

    3)
        echo -e ">>> 正在全數解除整個 Cache 資料夾的不可變屬性並還原權限..."
        if [ -d "$CACHE_DIR" ]; then
            sudo chattr -R -i "$CACHE_DIR" 2>/dev/null || true
            chmod -R 775 "$CACHE_DIR"
            echo -e "${GREEN}✓ 整個 Cache 資料夾已完全解鎖並還原為 775 權限！${NC}"
        else
            echo -e "${RED}錯誤：找不到 Cache 資料夾 ($CACHE_DIR)${NC}"
            exit 1
        fi
        ;;
esac

echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN} Zen Mode 設定完成！請重新啟動 LINE 體驗清靜視窗。  ${NC}"
echo -e "${GREEN}====================================================${NC}"
