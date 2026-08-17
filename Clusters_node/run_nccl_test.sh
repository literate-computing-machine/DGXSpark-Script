#!/bin/bash

# ==========================================
# 1. 使用者自定義區塊 (請根據你的實際情況修改)
# ==========================================
NODE1_IP="192.168.200.12"  # 填入 Node 1 的 IP
NODE2_IP="192.168.200.13"  # 填入 Node 2 的 IP
INTERFACE="enp1s0f1np1"  # 你的網卡名稱

# 確保路徑與之前的安裝一致
export CUDA_HOME="/usr/local/cuda"
export NCCL_HOME="$HOME/nccl/build"
export LD_LIBRARY_PATH="$NCCL_HOME/lib:$CUDA_HOME/lib64:$LD_LIBRARY_PATH"

# ==========================================
# 2. 設定 NCCL 與通訊環境變數
# ==========================================
export UCX_NET_DEVICES=$INTERFACE
export NCCL_SOCKET_IFNAME=$INTERFACE
export OMPI_MCA_btl_tcp_if_include=$INTERFACE

# 這裡設定 NCCL 的除錯等級，可以看到通訊細節 (1=正常, 2=詳細)
export NCCL_DEBUG=INFO 

# ==========================================
# 3. 執行 MPI 分散式測試
# ==========================================
echo "正在啟動 NCCL All_Gather 效能測試..."
echo "節點列表: $NODE1_IP, $NODE2_IP"

mpirun -np 2 \
  -H $NODE1_IP:1,$NODE2_IP:1 \
  --mca plm_rsh_agent "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" \
  -x LD_LIBRARY_PATH \
  -x UCX_NET_DEVICES \
  -x NCCL_SOCKET_IFNAME \
  -x NCCL_DEBUG \
  $HOME/nccl-tests/build/all_gather_perf -b 8 -e 128M -f 2 -g 1
