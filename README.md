# DGXSpark-Script

雙節點 NVIDIA DGX Spark 叢集的操作腳本，提供下列功能：

- 以 Docker、Ray 與 vLLM 建立分散式推論叢集
- 透過 NCCL `all_gather_perf` 測試節點間 GPU 通訊效能
- 使用 QSFP 網路同步 Hugging Face 模型快取
- 透過 Avahi 探索節點並設定共用 SSH 金鑰
- 以 Prometheus 與 Grafana 監控 vLLM

本專案的腳本預設以兩台機器運作：一台 Head Node，以及一台 Worker Node。

## 架構與預設設定

| 角色 | 預設 IP | 主要用途 |
| --- | --- | --- |
| Head Node / Node 1 | `192.168.200.12` | Ray Head、vLLM API、監控服務 |
| Worker Node / Node 2 | `192.168.200.13` | Ray Worker、GPU 計算 |

目前腳本中常見的預設值如下，請依實際環境修改：

- 高速網路介面：`enp1s0f1np1`
- Hugging Face 快取：`/home/islab/.cache/huggingface`
- vLLM 映像：`nvcr.io/nvidia/vllm:25.11-py3`
- 模型：`openai/gpt-oss-120b`
- Tensor parallel size：`2`
- vLLM API：`0.0.0.0:8000`

## 目錄結構

```text
.
├── Head_node/
│   ├── 2spark-vllm/
│   │   ├── run_cluster.sh              # 通用 Ray Docker 啟動器
│   │   ├── start_Ray_head_node.sh       # 啟動 Head Node
│   │   ├── start_vllm_service.sh        # 在 Ray 容器內啟動 vLLM
│   │   └── QSFP_rsync_hf.sh             # 透過 QSFP 同步模型快取
│   ├── monitor/
│   │   ├── docker-compose.yml           # Prometheus + Grafana
│   │   └── prometheus.yml               # vLLM metrics 設定
│   ├── run_nccl_test.sh                 # 8B～128M AllGather 測試
│   ├── run_nccl_16g_test.sh             # 固定 16GB AllGather 測試
│   └── discover-sparks                  # 探索節點並設定 SSH
└── Clusters_node/
    ├── 2spark-vllm/
    │   ├── run_cluster.sh               # 與 Head Node 相同的通用啟動器
    │   └── start_Ray_worker_node.sh      # 啟動 Worker Node
    ├── run_nccl_test.sh
    ├── run_nccl_16g_test.sh
    └── discover-sparks
```

`Head_node/` 與 `Clusters_node/` 中的 NCCL 測試及 `discover-sparks` 目前是各自存放的副本；修改其中一份時，請確認另一份是否也需要同步。

## 前置需求

兩台節點都需要具備：

- Linux、可正常使用的 NVIDIA Driver、CUDA 與 GPU
- Docker，以及可使用 GPU 的 NVIDIA Container Toolkit
- 可互相連線的高速網路介面；Ray 與 NCCL 腳本會使用 host network
- Python/工具環境中的 Ray 與 vLLM Docker 映像
- NCCL、`nccl-tests`、Open MPI、UCX
- `ssh`、`scp`、`rsync`、`ip`、`ibdev2netdev`
- 執行 `discover-sparks` 時需要 `avahi-browse`（通常由 `avahi-utils` 提供）

節點之間也必須能以 SSH 連線。NCCL 腳本透過 `mpirun` 在兩台節點上啟動程序，因此建議先確認使用者可以不需互動式密碼登入另一台節點。

> 注意：目前工作區內的腳本沒有 executable bit。可直接使用 `bash script.sh`，或在確認內容後執行 `chmod +x script.sh`。

## 快速開始：啟動 Ray 與 vLLM

### 1. 設定 Head Node

先修改 `Head_node/2spark-vllm/start_Ray_head_node.sh` 的 `MN_IF_NAME`，使其符合 Head Node 上的高速網卡名稱。腳本會從該介面自動取得 IP，並將 Ray Head 以背景程序啟動：

```bash
cd Head_node/2spark-vllm
sudo bash start_Ray_head_node.sh
tail -f vllm_head_*.log
```

預設會使用：

- Hugging Face 路徑：`/home/islab/.cache/huggingface`
- Ray Head port：`6379`
- 所有可見 GPU：`--gpus all`
- Docker shared memory：`10.24g`

### 2. 設定 Worker Node

修改 `Clusters_node/2spark-vllm/start_Ray_worker_node.sh` 的 `MN_IF_NAME`，然後在 Worker Node 執行。第一個參數是 Head Node 的高速網路 IP：

```bash
cd Clusters_node/2spark-vllm
sudo bash start_Ray_worker_node.sh 192.168.200.12
tail -f vllm_worker_*.log
```

Worker 會以 `VLLM_HOST_IP` 指定自己的高速網路 IP，並連線至：

```text
<head-node-ip>:6379
```

### 3. 在 Head Node 啟動 vLLM

確認 Ray Head 與 Worker 都已加入叢集後，在 Head Node 執行：

```bash
cd Head_node/2spark-vllm
sudo bash start_vllm_service.sh
tail -f vllm_server.log
```

服務啟動後，可在 Head Node 檢查模型 API：

```bash
curl http://127.0.0.1:8000/v1/models
```

`start_vllm_service.sh` 會尋找名稱符合 `node-<數字>` 的運作中容器，並在容器內執行：

```text
vllm serve openai/gpt-oss-120b \
  --host 0.0.0.0 \
  --port 8000 \
  --tensor-parallel-size 2 \
  --gpu-memory-utilization 0.9 \
  --trust-remote-code
```

### 4. 停止服務

查看目前的 Ray/vLLM 容器：

```bash
docker ps
```

通用啟動器會將容器命名為 `node-<random_suffix>`。停止該容器即可結束對應的 Ray 節點：

```bash
docker stop <container-name>
```

## 直接使用通用 Ray 啟動器

`run_cluster.sh` 的參數格式如下：

```text
bash run_cluster.sh <docker-image> <head-node-ip> --head|--worker <hf-cache-path> [docker arguments...]
```

Head Node 範例：

```bash
bash run_cluster.sh \
  nvcr.io/nvidia/vllm:25.11-py3 \
  192.168.200.12 \
  --head \
  /home/islab/.cache/huggingface \
  -e VLLM_HOST_IP=192.168.200.12
```

Worker Node 範例：

```bash
bash run_cluster.sh \
  nvcr.io/nvidia/vllm:25.11-py3 \
  192.168.200.12 \
  --worker \
  /home/islab/.cache/huggingface \
  -e VLLM_HOST_IP=192.168.200.13
```

此啟動器會：

- 使用 `--network host`，讓 Ray/NCCL 直接使用主機網路
- 將所有 GPU 傳入容器
- 將 Docker shared memory 設為 `10.24g`
- 將指定的 Hugging Face 快取掛載到 `/root/.cache/huggingface`
- 以 `ray start --block` 啟動 Head 或 Worker
- 程序結束時停止並移除該容器

## Hugging Face 快取同步

`Head_node/2spark-vllm/QSFP_rsync_hf.sh` 會使用 Head Node 的 QSFP IP，透過 `rsync` 將模型快取同步到一或多台 Worker。

執行前請修改腳本中的：

- `CACHE_DIR`：本機 Hugging Face 快取路徑
- `HEAD_QSFP_IP`：Head Node 的 QSFP 內網 IP
- `WORKER_IPS`：Worker 的 QSFP IP 清單
- `REMOTE_USER`：遠端登入使用者

執行：

```bash
cd Head_node/2spark-vllm
bash QSFP_rsync_hf.sh
```

此腳本會在遠端建立目標資料夾，並以 `ssh -b <HEAD_QSFP_IP>` 綁定來源 IP。請先確認 SSH 登入與 QSFP 路由正常。

## NCCL / AllGather 測試

Head Node 與 Worker Node 目錄各有一份測試腳本。執行前請在腳本中修改節點 IP 與 `INTERFACE`，並確認以下路徑符合實際安裝位置：

```bash
CUDA_HOME=/usr/local/cuda
NCCL_HOME=$HOME/nccl/build
$HOME/nccl-tests/build/all_gather_perf
```

一般測試會測量 8B 到 128M 的 AllGather：

```bash
bash Head_node/run_nccl_test.sh
```

16GB 壓力測試只測固定的 16GB payload：

```bash
bash Head_node/run_nccl_16g_test.sh
```

兩支腳本目前都設定為兩個 MPI process、每個節點使用一張 GPU（`-g 1`），並輸出 `NCCL_DEBUG=INFO`。測試使用 SSH 啟動遠端程序，請先確認兩台機器間的 SSH 與網卡設定。

## 節點探索與 SSH 設定

`discover-sparks` 會：

1. 透過 `ibdev2netdev` 找出狀態為 `Up` 的網路介面。
2. 使用 `avahi-browse` 搜尋這些介面上的 `_ssh._tcp` 服務。
3. 收集並排序可用的 IPv4 位址。
4. 建立 `$HOME/.ssh/id_ed25519_shared`（若尚未存在）。
5. 將共用金鑰配置到探索到的節點，並更新 SSH config。

請以一般使用者執行，不要使用 `sudo`：

```bash
bash Head_node/discover-sparks
```

此腳本會修改本機與遠端的 `~/.ssh`，而且會將同一把私鑰複製到節點。正式環境使用前，請先審閱腳本並確認這符合你的安全規範。

## Prometheus 與 Grafana 監控

`Head_node/monitor/docker-compose.yml` 會啟動：

- Prometheus：`http://<head-node-ip>:9090`
- Grafana：`http://<head-node-ip>:3000`

啟動監控：

```bash
cd Head_node/monitor
docker compose up -d
```

停止監控：

```bash
docker compose down
```

Prometheus 每 5 秒抓取 `host.docker.internal:8000/metrics`。Grafana 使用環境變數設定管理員帳號與密碼；密碼不會寫入 repository。啟動前請先設定：

```bash
export GF_SECURITY_ADMIN_USER=islab
export GF_SECURITY_ADMIN_PASSWORD='請替換成強密碼'
```

接著執行 `docker compose up -d`。請勿將含有真實密碼的 `.env` 檔或 Shell history 提交到 Git，並在對外開放 Grafana 前補上適當的網路存取控制。

## 常見問題

### 找不到網路 IP

確認腳本中的 `MN_IF_NAME` 與實際介面一致：

```bash
ip -4 addr show <interface-name>
ibdev2netdev
```

### Worker 無法加入 Ray

確認下列項目：

- Worker 可以連線到 Head 的 `6379` port
- Head 與 Worker 使用正確且互通的高速網路 IP
- `VLLM_HOST_IP` 對每台 Worker 都是唯一值
- Docker 使用 `--network host`
- 防火牆沒有阻擋 Ray、NCCL 或 MPI 所需的連線
- Head Node 的 `tail -f vllm_head_*.log` 與 Worker Node 的 `tail -f vllm_worker_*.log` 沒有錯誤

### 找不到 vLLM 容器

`start_vllm_service.sh` 只會搜尋正在執行且名稱符合 `node-<數字>` 的容器。請先確認 Head 啟動腳本已成功執行：

```bash
docker ps
```

### vLLM 使用的網卡與 Ray 網卡不一致

Ray 啟動腳本預設使用 `enp1s0f1np1`；`start_vllm_service.sh` 目前另設為 `enP2p1s0f1np`。請依實際環境檢查並統一 `IF_NAME`，特別注意大小寫與拼字。

### `MAX_LEN` 沒有生效

`start_vllm_service.sh` 雖然宣告了 `MAX_LEN=4096`，但 `--max-model-len` 目前被註解，因此實際啟動時不會套用這個值。需要限制 context length 時，請先確認模型需求，再取消該參數的註解。

## 設定檔速查

| 需求 | 修改位置 |
| --- | --- |
| Head 網卡 | `Head_node/2spark-vllm/start_Ray_head_node.sh` 的 `MN_IF_NAME` |
| Worker 網卡 | `Clusters_node/2spark-vllm/start_Ray_worker_node.sh` 的 `MN_IF_NAME` |
| vLLM 映像 | `VLLM_IMAGE` 環境變數或 Head/Worker 啟動腳本預設值 |
| 模型、TP、GPU 使用率 | `Head_node/2spark-vllm/start_vllm_service.sh` |
| Hugging Face 快取路徑 | Head/Worker 啟動腳本與 `QSFP_rsync_hf.sh` |
| NCCL 節點 IP 與網卡 | `run_nccl_test.sh`、`run_nccl_16g_test.sh` |
| Prometheus 抓取目標 | `Head_node/monitor/prometheus.yml` |
| Grafana 帳密 | `Head_node/monitor/docker-compose.yml` |

## 授權

本專案目前未提供額外的專案授權檔。`discover-sparks` 腳本內含 NVIDIA Apache License 2.0 標頭；如需對外發布或整合，請依各腳本原始授權與第三方元件授權辦理。


## 可參考資料：
[NVIDIA_Forums - GB10](https://forums.developer.nvidia.com/c/accelerated-computing/dgx-spark-gb10/719)

[OKHand Blog - Dgx Spark Cluster Interconnect](https://okhand.org/zh-tw/posts/dgx-spark-cluster-interconnect/)

[NVIDIA Github - dgx-spark-playbooks](https://github.com/NVIDIA/dgx-spark-playbooks)

[NVIDIA - Connect Two Sparks](https://build.nvidia.com/spark/connect-two-sparks/stacked-sparks)

[NVIDIA - NCCL for Two Sparks](https://build.nvidia.com/spark/nccl/stacked-sparks)

[Github - eugr/spark-vllm-docker](https://github.com/eugr/spark-vllm-docker)
