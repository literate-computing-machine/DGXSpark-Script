#!/bin/bash

# ==========================================
# 1. 環境變數設定 (請根據實際 IP 修改)
# ==========================================
NODE1="192.168.200.12"
NODE2="192.168.200.13"
INTERFACE="enp1s0f1np1"

# 自動匯入當前 Shell 的路徑設定
export CUDA_HOME="/usr/local/cuda"
export NCCL_HOME="$HOME/nccl/build"
export LD_LIBRARY_PATH="$NCCL_HOME/lib:$CUDA_HOME/lib64:$LD_LIBRARY_PATH"

# 設定網路接口
export UCX_NET_DEVICES=$INTERFACE
export NCCL_SOCKET_IFNAME=$INTERFACE
export OMPI_MCA_btl_tcp_if_include=$INTERFACE

# 增加除錯資訊，以便觀察 16G 傳輸時的狀態
export NCCL_DEBUG=INFO

# 關鍵修正：嘗試在執行前解除系統限制 (需要當前使用者有權限)
#ulimit -l unlimited

# ==========================================
# 2. 執行 16G 大數據量測試
# ==========================================
# 參數說明：
# -b 16G : 起始數據大小 16GB
# -e 16G : 結束數據大小 16GB (只測這個固定大小)
# -f 2   : 步進倍率 (此處因起點終點相同，無實質影響)
# -g 1   : 每個節點使用 1 顆 GPU
# ==========================================

echo "正在啟動 NCCL All_Gather 16GB 壓力測試..."

mpirun -np 2 -H $NODE1:1,$NODE2:1 \
  --mca plm_rsh_agent "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" \
  -x LD_LIBRARY_PATH \
  -x UCX_NET_DEVICES \
  -x NCCL_SOCKET_IFNAME \
  -x NCCL_DEBUG \
  $HOME/nccl-tests/build/all_gather_perf -b 16G -e 16G -f 2 -g 1
