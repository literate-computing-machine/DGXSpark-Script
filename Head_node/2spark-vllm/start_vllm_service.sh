#!/bin/bash

# --- 參數設定 ---
MODEL_PATH="openai/gpt-oss-120b"
TP_SIZE=2
MAX_LEN=4096
GPU_UTIL=0.9
LOG_FILE="vllm_server.log"

IF_NAME="enP2p1s0f1np"

# --- 自動抓取 vLLM 容器名稱 ---
VLLM_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E '^node-[0-9]+$')

# --- 檢查容器是否存在 ---
if [ -z "$VLLM_CONTAINER" ]; then
    echo "❌ 錯誤: 找不到運作中的 vLLM 容器！"
    echo "請確認你已經在 Node 1 執行過 Step 4 (run_cluster.sh --head)。"
    exit 1
fi

echo "✅ 找到容器: $VLLM_CONTAINER"
echo "🚀 正在將 vLLM 服務啟動於背景..."
echo "📍 API 地址將設為: http://0.0.0.0:8000"
echo "📝 日誌輸出檔案: $LOG_FILE"

# --- 執行背景推論服務 ---
# 1. --host 0.0.0.0 --port 8000: 開放 API 存取
# 2. > $LOG_FILE 2>&1: 將標準輸出與錯誤輸出都導向到日誌檔
# 3. &: 放在背景執行
docker exec $VLLM_CONTAINER /bin/bash -c "
  export NCCL_SOCKET_IFNAME=$IF_NAME && \
  export GLOO_SOCKET_IFNAME=$IF_NAME && \
  vllm serve ${MODEL_PATH} \
    --host 0.0.0.0 \
    --port 8000 \
    --tensor-parallel-size ${TP_SIZE} \
#    --max-model-len ${MAX_LEN} \
    --gpu-memory-utilization ${GPU_UTIL} \
    --trust-remote-code
" > "$LOG_FILE" 2>&1 &

# 取得剛才啟動的背景 PID (選用資訊)
BGPID=$!

echo "---------------------------------------------------"
echo "✅ 啟動指令已送出 (Background PID: $BGPID)"
echo "💡 提示: 模型較大，載入需要一段時間。"
echo "🔍 請執行以下指令查看啟動進度："
echo "   tail -f $LOG_FILE"
echo "---------------------------------------------------"
