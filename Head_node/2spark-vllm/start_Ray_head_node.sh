#!/bin/bash

# --- 設定區域 ---
# 如果你沒在環境變數設定 VLLM_IMAGE，腳本會預設使用這個版本
export VLLM_IMAGE=${VLLM_IMAGE:-"nvcr.io/nvidia/vllm:25.11-py3"}
export MN_IF_NAME="enp1s0f1np1"
LOG_FILE="vllm_head_$(date +%Y%m%d_%H%M%S).log"

# --- 自動獲取 IP ---
export VLL_HOST_IP=$(ip -4 addr show $MN_IF_NAME | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

if [ -z "$VLL_HOST_IP" ]; then
    echo "錯誤: 無法從介面 $MN_IF_NAME 獲取 IP。請檢查網路設定。"
    exit 1
fi

echo "------------------------------------------------"
echo "正在啟動 vLLM Head Node..."
echo "介面: $MN_IF_NAME"
echo "IP 位址: $VLL_HOST_IP"
echo "鏡像版本: $VLLM_IMAGE"
echo "日誌檔案: $LOG_FILE"
echo "------------------------------------------------"

# --- 背景執行指令 ---
# 使用 nohup 確保斷開 SSH 後不會中斷，並將輸出導向到日誌檔
nohup bash run_cluster.sh $VLLM_IMAGE $VLL_HOST_IP --head /home/islab/.cache/huggingface \
  -e VLLM_HOST_IP=$VLL_HOST_IP \
  -e UCX_NET_DEVICES=$MN_IF_NAME \
  -e NCCL_SOCKET_IFNAME=$MN_IF_NAME \
  -e OMPI_MCA_btl_tcp_if_include=$MN_IF_NAME \
  -e GLOO_SOCKET_IFNAME=$MN_IF_NAME \
  -e TP_SOCKET_IFNAME=$MN_IF_NAME \
  -e RAY_memory_monitor_refresh_ms=0 \
  -e MASTER_ADDR=$VLL_HOST_IP >> "$LOG_FILE" 2>&1 &

# 取得背景執行的 PID
PID=$!
echo "服務已在背景啟動 (PID: $PID)"
echo "你可以執行 'tail -f $LOG_FILE' 來查看即時日誌。"
