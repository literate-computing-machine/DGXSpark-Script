#!/bin/bash

# ==========================================
# 參數設定區
# ==========================================
# 1. Hugging Face 快取路徑 (結尾務必保留斜線 '/')
CACHE_DIR="$HOME/.cache/huggingface/"

# 2. ⚡ [重要新增] Head Node 的 QSFP 內網 IP (來源端)
# 這會強制 rsync 從這張網卡把資料送出去
HEAD_QSFP_IP="192.168.200.12"

# 3. ⚡ [重要確認] Worker 節點的 QSFP 內網 IP 列表 (接收端)
WORKER_IPS=(
    "192.168.200.13"
)

# 4. 使用者名稱
REMOTE_USER="$USER"

# ==========================================
# 執行區
# ==========================================
echo "🚀 啟動 QSFP 專線強制綁定傳輸..."
echo "綁定來源 IP: $HEAD_QSFP_IP"

for IP in "${WORKER_IPS[@]}"; do
    echo "---------------------------------------------------"
    echo "🔄 正在透過 QSFP 同步至 Worker: ${IP}"
    
    # 確保 Worker 節點上有目標資料夾
    ssh "${REMOTE_USER}@${IP}" "mkdir -p ${CACHE_DIR}"

    # 核心指令升級說明：
    # 加入了 -e "ssh -b ${HEAD_QSFP_IP}" 
    # 這會強迫底層的 SSH 隧道綁定在 Head Node 的 QSFP IP 上，絕對不走 10G 外網！
    rsync -avP \
          -e "ssh -b ${HEAD_QSFP_IP}" \
          "$CACHE_DIR" \
          "${REMOTE_USER}@${IP}:${CACHE_DIR}"

    if [ $? -eq 0 ]; then
        echo "✅ ${IP} 同步完成！"
    else
        echo "❌ ${IP} 同步失敗，請檢查網路。"
    fi
done

echo "==================================================="
echo "🎉 QSFP 極速同步完畢！"
