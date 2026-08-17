#!/bin/bash

# --- 設定區域 ---
export VLLM_IMAGE=${VLLM_IMAGE:-"nvcr.io/nvidia/vllm:25.11-py3"}
export MN_IF_NAME="enp1s0f1np1"
LOG_FILE="vllm_worker_$(date +%Y%m%d_%H%M%S).log"

# --- 檢查輸入參數 ---
if [ -z "$1" ]; then
    echo "錯誤: 請提供 Node 1 (Head Node) 的 IP 位址。"
    echo "用法: $0 <NODE_1_IP>"
    exit 1
fi

export HEAD_NODE_IP=$1

# --- 自動獲取本機 (Node 2) IP ---
export VLLM_HOST_IP=$(ip -4 addr show $MN_IF_NAME | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

if [ -z "$VLLM_HOST_IP" ]; then
    echo "錯誤: 無法從介面 $MN_IF_NAME 獲取 IP。請檢查網路設定。"
    exit 1
fi

echo "------------------------------------------------"
echo "正在啟動 vLLM Worker Node 並連向 Head..."
echo "本機 Worker IP: $VLLM_HOST_IP"
echo "連往 Head IP:   $HEAD_NODE_IP"
echo "鏡像版本:       $VLLM_IMAGE"
echo "日誌檔案:       $LOG_FILE"
echo "------------------------------------------------"

# --- 背景執行 Worker 指令 ---
nohup bash run_cluster.sh $VLLM_IMAGE $HEAD_NODE_IP --worker /home/islab/.cache/huggingface \
  -e VLLM_HOST_IP=$VLLM_HOST_IP \
  -e UCX_NET_DEVICES=$MN_IF_NAME \
  -e NCCL_SOCKET_IFNAME=$MN_IF_NAME \
  -e OMPI_MCA_btl_tcp_if_include=$MN_IF_NAME \
  -e GLOO_SOCKET_IFNAME=$MN_IF_NAME \
  -e TP_SOCKET_IFNAME=$MN_IF_NAME \
  -e RAY_memory_monitor_refresh_ms=0 \
  -e MASTER_ADDR=$HEAD_NODE_IP >> "$LOG_FILE" 2>&1 &

PID=$!
echo "Worker 已在背景啟動 (PID: $PID)"
echo "請執行 'tail -f $LOG_FILE' 查看連線狀態。"
