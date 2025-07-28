# Gravity 2.0 手動部署詳細操作步驟

## 📋 目錄
- [系統需求檢查](#系統需求檢查)
- [環境準備](#環境準備)
- [配置檔案修改](#配置檔案修改)
- [完整部署流程 (PostgreSQL版本)](#完整部署流程-postgresql版本)
- [部署驗證](#部署驗證)
- [常見問題排除](#常見問題排除)

## 🔍 系統需求檢查

### 1. Kubernetes 叢集檢查
```bash
# 檢查 Kubernetes 版本 (需要 v1.20+)
kubectl version --short

# 檢查叢集節點狀態
kubectl get nodes -o wide

# 檢查叢集資源使用狀況
kubectl top nodes
```

### 2. Storage Class 檢查
```bash
# 檢查可用的 Storage Class
kubectl get storageclass

# 檢查預設 Storage Class
kubectl get storageclass -o wide | grep "(default)"

# 如果沒有預設 Storage Class，設定一個
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### 3. 網路連通性檢查
```bash
# 檢查 DNS 解析
nslookup kubernetes.default.svc.cluster.local

# 檢查 Pod 網路
kubectl run test-pod --image=busybox --rm -it --restart=Never -- ping 8.8.8.8
```

## 🛠️ 環境準備

### 1. 下載部署檔案
```bash
# 克隆或下載 Gravity 部署配置
git clone <your-gravity-repo>
cd gravity-deployment

# 檢查所有必要檔案是否存在
ls -la *.yaml
```

### 2. 檢查映像檔可用性
```bash
# 檢查 NATS 映像檔
docker pull ghcr.io/brobridgeorg/nats-server:v1.3.25-20250701

# 檢查 Dispatcher 映像檔
docker pull ghcr.io/brobridgeorg/gravity-dispatcher:v0.0.31-20250701

# 檢查 Adapter 映像檔
docker pull ghcr.io/brobridgeorg/gravity-adapter-mssql:v3.0.9-20240909
docker pull ghcr.io/brobridgeorg/gravity-adapter-postgres:v2.0.8-20250601

# 檢查 Atomic 映像檔
docker pull ghcr.io/brobridgeorg/atomic/atomic:v0.0.5-20231012-ubi
```

## ⚙️ 配置檔案修改

### 1. 修改 ConfigMap (00-lab-configmap.yaml)
```bash
# 編輯 ConfigMap
vi 00-lab-configmap.yaml
```

**必須修改的參數：**
```yaml
data:
  # 時區設定
  TZ: Asia/Taipei
  
  # MSSQL 來源配置 (如果使用 MSSQL)
  SOURCE_DATABASE_HOST: "your-mssql-server-ip"
  SOURCE_DB_MSSQL_DB_NAME: "YourDatabase"
  SOURCE_DB_MSSQL_TB1_NAME: "your_table_name"
  SOURCE_DATABASE_USER: "SA"
  
  # PostgreSQL 來源配置 (如果使用 PostgreSQL)
  SOURCE_POSTGRES_HOST: "your-postgres-server-ip"
  SOURCE_POSTGRES_DB_NAME: "your_database"
  SOURCE_POSTGRES_TB1_NAME: "your_table_name"
  SOURCE_POSTGRES_USER: "postgres"
  
  # MySQL 目標配置
  TARGET_DB_MYSQL_HOST: "your-mysql-server-ip"
  TARGET_DB_MYSQL_DB_NAME: "target_database"
  TARGET_DB_MYSQL_TB1_NAME: "target_table"
  TARGET_DB_MYSQL_USER: "mysql_user"
  
  # Gitea 配置
  GIT_URL: "your-gitea-server:3000"
  GIT_TOKEN: "your-gitea-access-token"
  GIT_REPO_URL: "your-username/your-repo.git"
  GIT_USER: "your-gitea-username"
```

### 2. 修改 Secret (01-lab-secret.yaml)
```bash
# 產生 Base64 編碼的密碼
echo -n "your-mssql-password" | base64
echo -n "your-postgres-password" | base64
echo -n "your-mysql-password" | base64

# 編輯 Secret 檔案
vi 01-lab-secret.yaml
```

**更新密碼：**
```yaml
data:
    db_source_mssql_password: <your-base64-encoded-mssql-password>
    db_source_postgres_password: <your-base64-encoded-postgres-password>
    db_target_mysql_password: <your-base64-encoded-mysql-password>
```

### 3. 修改 Adapter 配置
**對於 MSSQL Adapter (30-lab-adapter-mssql.yaml)：**
```yaml
# 更新資料表設定
- name: GRAVITY_ADAPTER_MSSQL_SOURCE_SETTINGS
  value: |
    {
      "sources": {
        "mssql_source": {
          "host": "your-mssql-host",
          "port": 1433,
          "username": "SA",
          "dbname": "YourDatabase",
          "tables": {
            "dbo.your_table_name":{
              "events": {
                "snapshot": "yourTableInitialize",
                "create": "yourTableCreate",
                "update": "yourTableUpdate",
                "delete": "yourTableDelete"
              }
            }
          }
        }
      }
    }
```

## 🚀 完整部署流程 (PostgreSQL版本)

### 推薦部署順序
**Gitea → NATS → Atomic → Dispatcher → PostgreSQL Adapter**

### 步驟 0：部署 Gitea (建議先部署)
```bash
# 部署 Gitea
kubectl apply -f 50-gitea-deployment.yaml

# 監控 Gitea 部署狀態
kubectl -n gitea get pods -w

# 等待 Gitea 準備就緒
kubectl -n gitea wait --for=condition=ready pod --selector=app=gitea --timeout=300s

# 檢查 Gitea 服務
kubectl -n gitea get svc gitea

# 取得訪問 URL
echo "Gitea 訪問地址: http://<node-ip>:31300"
```

**Gitea 初始設定：**
1. 瀏覽器開啟 `http://<node-ip>:31300`
2. 完成初始安裝設定
3. 建立管理員帳戶
4. 建立 Repository (例如: `demo/gravity2-lab.git`)
5. 產生 Access Token
6. 記錄 Token 用於後續配置

### 步驟 1：建立 Gravity Namespace 和基礎配置
```bash
# 建立 Gravity 命名空間
kubectl apply -f namespace.yaml

# 部署 ConfigMap (確保 Git 設定正確)
kubectl apply -f 00-lab-configmap.yaml

# 部署 Secret
kubectl apply -f 01-lab-secret.yaml

# 驗證配置部署
kubectl -n gravity2-lab get configmap labcm
kubectl -n gravity2-lab get secret labsecret
```

### 步驟 2：部署 NATS 叢集
```bash
# 部署 NATS StatefulSet (3個副本叢集)
kubectl apply -f 10-lab-gravity-nats.yaml

# 監控 NATS 部署狀態
kubectl -n gravity2-lab get pods -l app=gravity,component=nats -w

# 等待所有 NATS Pod 準備就緒 (預期 3 個 Pod)
kubectl -n gravity2-lab wait --for=condition=ready pod --selector=app=gravity,component=nats --timeout=600s

# 檢查 NATS 服務
kubectl -n gravity2-lab get svc -l app=gravity,component=nats

# 驗證 NATS 叢集健康狀態
kubectl -n gravity2-lab exec -t lab-gravity-nats-0 -- /nats server check connection
kubectl -n gravity2-lab exec -t lab-gravity-nats-0 -- /nats server list
```

### 步驟 3：部署 Atomic (Low-Code 處理引擎)
```bash
# 部署 Atomic Deployment
kubectl apply -f 40-lab-atomic.yaml

# 監控 Atomic 部署狀態
kubectl -n gravity2-lab get pods -l app=atomic -w

# 等待 Atomic 準備就緒
kubectl -n gravity2-lab wait --for=condition=ready pod --selector=app=atomic --timeout=300s

# 檢查 Atomic 服務 (NodePort 32300)
kubectl -n gravity2-lab get svc lab-atomic

# 檢查 Atomic 日誌 (確認 Git clone 成功)
kubectl -n gravity2-lab logs deployment/lab-atomic-atomic -c init-lab-atomic-git
kubectl -n gravity2-lab logs deployment/lab-atomic-atomic -c lab-atomic

# 取得 Atomic 訪問 URL
echo "Atomic 訪問地址: http://<node-ip>:32300"
```

### 步驟 4：部署 Dispatcher (系統管理器)
```bash
# 部署 Dispatcher StatefulSet
kubectl apply -f 20-lab-gravity-dispatcher.yaml

# 監控 Dispatcher 部署狀態
kubectl -n gravity2-lab get pods -l app=gravity,component=dispatcher -w

# 等待 Dispatcher 準備就緒
kubectl -n gravity2-lab wait --for=condition=ready pod --selector=app=gravity,component=dispatcher --timeout=300s

# 檢查 Dispatcher 日誌
kubectl -n gravity2-lab logs lab-gravity-dispatcher-0
```

### 步驟 5：部署 PostgreSQL Adapter (最後部署)
```bash
# 部署 PostgreSQL Adapter StatefulSet
kubectl apply -f 30-lab-adapter-postgres.yaml

# 監控 Adapter 部署狀態
kubectl -n gravity2-lab get pods -l app=gravity-adapter,component=postgres -w

# 等待 Adapter 準備就緒
kubectl -n gravity2-lab wait --for=condition=ready pod --selector=app=gravity-adapter,component=postgres --timeout=300s

# 檢查 Adapter 日誌 (確認資料庫連線)
kubectl -n gravity2-lab logs lab-adapter-postgres-0
```

### 步驟 6：完整系統驗證
```bash
# 檢查所有 Pod 狀態
kubectl -n gravity2-lab get pods -o wide
kubectl -n gitea get pods -o wide

# 檢查所有服務
kubectl -n gravity2-lab get svc
kubectl -n gitea get svc

# 檢查 NATS 叢集狀態
kubectl -n gravity2-lab exec -t lab-gravity-nats-0 -- /nats server list
kubectl -n gravity2-lab exec -t lab-gravity-nats-0 -- /nats str ls

# 檢查資料庫連線 (從 Adapter 日誌)
kubectl -n gravity2-lab logs lab-adapter-postgres-0 | grep -i "connect\|error\|ready"
```

## ✅ 部署驗證

### 1. 檢查所有 Pod 狀態
```bash
# 檢查 Gravity 相關 Pod
kubectl -n gravity2-lab get pods -o wide

# 檢查 Gitea Pod
kubectl -n gitea get pods -o wide

# 檢查所有服務
kubectl -n gravity2-lab get svc
kubectl -n gitea get svc
```

### 2. 檢查 NATS 叢集狀態
```bash
# 檢查 NATS 叢集健康狀態
kubectl -n gravity2-lab exec -t lab-gravity-nats-0 -- /nats server list

# 檢查 NATS Stream
kubectl -n gravity2-lab exec -t lab-gravity-nats-0 -- /nats str ls

# 檢查 NATS 監控
kubectl -n gravity2-lab exec -t lab-gravity-nats-0 -- /nats server check connection
```

### 3. 測試資料庫連線
```bash
# 檢查 Adapter 連線狀態 (以 MSSQL 為例)
kubectl -n gravity2-lab logs lab-adapter-mssql-0 | grep -i "connect"

# 檢查 Dispatcher 狀態
kubectl -n gravity2-lab logs lab-gravity-dispatcher-0 | grep -i "ready"
```

## 🧪 功能測試

### 1. 使用 Gravity-CLI 測試
```bash
# 設定連線參數
export GRAVITY_HOST="lab-gravity-nats"
export GRAVITY_PORT="4222"
export GRAVITY_DOMAIN="default"

# 如果在叢集外，使用 Port Forward
kubectl -n gravity2-lab port-forward svc/lab-gravity-nats 4222:4222 &

# 建立 Data Product
gravity-cli product create testdp --desc="Test Data Product" --enabled -s localhost:4222

# 列出 Data Products
gravity-cli product list -s localhost:4222
```

### 2. 資料流測試
```bash
# 在來源資料庫執行資料異動
# 檢查 Adapter 日誌是否捕獲到變更
kubectl -n gravity2-lab logs lab-adapter-mssql-0 -f

# 檢查 NATS 是否有新訊息
kubectl -n gravity2-lab exec -t lab-gravity-nats-0 -- /nats str info GVT_default_DP_testdp
```

## 🛠️ 常見問題排除

### 1. Pod 無法啟動
```bash
# 查看 Pod 事件
kubectl -n gravity2-lab describe pod <pod-name>

# 檢查映像檔拉取狀態
kubectl -n gravity2-lab get events --sort-by='.lastTimestamp'

# 檢查資源限制
kubectl -n gravity2-lab top pods
kubectl describe node <node-name>
```

### 2. Storage 問題
```bash
# 檢查 PVC 狀態
kubectl -n gravity2-lab get pvc

# 檢查 Storage Class
kubectl get storageclass

# 查看 PV 詳情
kubectl get pv
```

### 3. 網路連線問題
```bash
# 檢查服務端點
kubectl -n gravity2-lab get endpoints

# 測試服務連通性
kubectl -n gravity2-lab exec -it <pod-name> -- nc -zv <service-name> <port>

# 檢查 DNS 解析
kubectl -n gravity2-lab exec -it <pod-name> -- nslookup <service-name>
```

### 4. 資料庫連線問題
```bash
# 檢查 ConfigMap 配置
kubectl -n gravity2-lab get configmap labcm -o yaml

# 檢查 Secret 配置
kubectl -n gravity2-lab get secret labsecret -o yaml

# 測試資料庫連線 (從 Pod 內部)
kubectl -n gravity2-lab exec -it lab-adapter-mssql-0 -- sh
# 在 Pod 內執行連線測試
```

### 5. Gitea 連線問題
```bash
# 檢查 Gitea 服務狀態
kubectl -n gitea get pods
kubectl -n gitea get svc

# 檢查 NodePort 服務
kubectl get svc -A | grep NodePort

# 測試從 Gravity Pod 到 Gitea 的連線
kubectl -n gravity2-lab exec -it <pod-name> -- nc -zv gitea.gitea.svc.cluster.local 3000
```

## 📝 部署清單

完成以下檢查項目，確保部署成功：

- [ ] Kubernetes 叢集運行正常
- [ ] Storage Class 配置正確
- [ ] ConfigMap 和 Secret 已更新
- [ ] NATS 叢集 (3 個 Pod) 運行正常
- [ ] Dispatcher 運行正常
- [ ] 資料庫 Adapter 運行正常
- [ ] Gitea 部署並可訪問
- [ ] 所有服務網路互通
- [ ] Gravity-CLI 可以連線
- [ ] 資料流測試通過

## 🌐 服務訪問資訊

部署完成後，您可以通過以下方式訪問服務：

### Web 服務
- **Gitea**: `http://<node-ip>:31300` - Git 版本控制和儲存庫管理
- **Atomic**: `http://<node-ip>:32300` - Low-Code 資料處理流程設計

### CLI 連線
```bash
# 設定 Gravity CLI 連線參數
export GRAVITY_HOST="lab-gravity-nats"
export GRAVITY_PORT="4222"
export GRAVITY_DOMAIN="default"

# 如果在叢集外，使用 Port Forward
kubectl -n gravity2-lab port-forward svc/lab-gravity-nats 4222:4222 &

# 然後使用 localhost:4222 連線
gravity-cli product list -s localhost:4222
```

### 監控服務
```bash
# NATS 監控界面
kubectl -n gravity2-lab port-forward svc/lab-gravity-nats-mgmt 8222:8222 &
# 訪問: http://localhost:8222

# 檢查服務狀態
kubectl -n gravity2-lab get pods -o wide
kubectl -n gitea get pods -o wide
```

## 🚀 後續配置和使用

### 1. Gitea Repository 設定
1. 訪問 Gitea Web 界面建立 Repository
2. 在 Atomic 中配置資料處理流程
3. 使用 Gravity CLI 建立 Data Product

### 2. 資料流測試
```bash
# 在 PostgreSQL 來源資料庫執行測試
INSERT INTO your_table_name (id, name, value) VALUES (1, 'test', 'data');
UPDATE your_table_name SET value = 'updated' WHERE id = 1;
DELETE FROM your_table_name WHERE id = 1;

# 檢查 Adapter 日誌是否捕獲到變更
kubectl -n gravity2-lab logs lab-adapter-postgres-0 -f
```

### 3. 監控和維護
- 定期檢查 Pod 狀態和資源使用
- 監控 NATS 叢集健康狀態
- 備份 Gitea 資料和配置檔案

---

## 📝 部署清單

完成以下檢查項目，確保 PostgreSQL 版本 Gravity 部署成功：

- [ ] Gitea 部署並可訪問 (http://<node-ip>:31300)
- [ ] Gitea Repository 建立完成
- [ ] Access Token 獲取並更新到 ConfigMap
- [ ] NATS 叢集 (3 個 Pod) 運行正常
- [ ] Atomic 部署並可訪問 (http://<node-ip>:32300)
- [ ] Dispatcher 運行正常
- [ ] PostgreSQL Adapter 運行正常
- [ ] 所有服務網路互通
- [ ] PostgreSQL 資料庫連線成功
- [ ] 資料流測試通過

**完成部署後，您的 Gravity 2.0 系統應該能夠正常捕獲 PostgreSQL 資料庫變更並進行即時處理。**