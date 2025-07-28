# Gravity 2.0 PostgreSQL 版本完整部署指南

## 📋 目錄
- [系統環境要求](#系統環境要求)
- [部署檔案清單](#部署檔案清單)
- [配置檔案修改](#配置檔案修改)
- [完整部署流程](#完整部署流程)
- [訪問和驗證](#訪問和驗證)
- [常見問題解決](#常見問題解決)

## 🔍 系統環境要求

### Kubernetes 叢集需求
- Kubernetes v1.20+
- kubectl 命令工具已安裝
- 預設 Storage Class 已配置
- 叢集節點間網路互通

### 檢查命令
```bash
# 檢查 Kubernetes 版本
kubectl version --short

# 檢查節點狀態
kubectl get nodes -o wide

# 檢查 Storage Class
kubectl get storageclass
```

## 📁 部署檔案清單

確保以下檔案存在於部署目錄中：

```
├── namespace.yaml                    # Namespace 定義
├── 00-lab-configmap.yaml           # 配置映射
├── 01-lab-secret.yaml              # 密碼配置
├── 10-lab-gravity-nats.yaml        # NATS 叢集
├── 20-lab-gravity-dispatcher.yaml  # Dispatcher
├── 30-lab-adapter-postgres.yaml    # PostgreSQL Adapter
├── 40-lab-atomic.yaml              # Atomic 引擎
└── 50-gitea-deployment.yaml        # Gitea 服務
```

## ⚙️ 配置檔案修改

### 1. 修改 ConfigMap (00-lab-configmap.yaml)

**重要：修改以下參數以符合您的環境**

```yaml
data:
  TZ: Asia/Taipei
  
  # PostgreSQL 來源配置
  SOURCE_POSTGRES_HOST: "your-postgres-server-ip"
  SOURCE_POSTGRES_PORT: "5432"
  SOURCE_POSTGRES_DB_NAME: "your_database"
  SOURCE_POSTGRES_TB1_NAME: "your_table_name"
  SOURCE_POSTGRES_USER: "postgres"
  
  # MySQL 目標配置
  TARGET_DB_MYSQL_HOST: "your-mysql-server-ip"
  TARGET_DB_MYSQL_PORT: "3306"
  TARGET_DB_MYSQL_DB_NAME: "target_database"
  TARGET_DB_MYSQL_TB1_NAME: "target_table"
  TARGET_DB_MYSQL_USER: "mysql_user"
  
  # Git 配置 (後續會更新)
  GIT_BRANCH: master
  GIT_REPO_URL: gravity/gravity.git
  GIT_TOKEN: "your-gitea-access-token"
  GIT_URL: "10.10.7.210:31300"
  GIT_USER: "gravity"
```

### 2. 修改 Secret (01-lab-secret.yaml)

```bash
# 生成 Base64 編碼的密碼
echo -n "your-postgres-password" | base64
echo -n "your-mysql-password" | base64

# 編輯 Secret 檔案，更新密碼
vi 01-lab-secret.yaml
```

```yaml
data:
  db_source_postgres_password: <your-base64-encoded-postgres-password>
  db_target_mysql_password: <your-base64-encoded-mysql-password>
```

## 🚀 完整部署流程

### 步驟 0：部署 Gitea（必須先部署）

#### 0.1 部署 Gitea 服務
```bash
# 部署 Gitea
kubectl apply -f 50-gitea-deployment.yaml

# 監控部署狀態
kubectl -n gitea get pods -w

# 等待 Gitea 準備就緒
kubectl -n gitea wait --for=condition=ready pod --selector=app=gitea --timeout=300s

# 檢查服務
kubectl -n gitea get svc gitea
```

#### 0.2 初始化 Gitea Repository

**方式一：通過 Web 界面**
1. 取得節點 IP：`kubectl get nodes -o wide`
2. 訪問 `http://<node-ip>:31300`
3. 完成 Gitea 初始設定，創建管理員帳戶
4. 創建名為 `gravity` 的組織
5. 在組織下創建名為 `gravity` 的 Repository
6. 生成 Access Token（Settings → Applications → Generate New Token）

**方式二：通過命令行初始化**
```bash
# 創建臨時目錄並初始化 Repository
mkdir -p ~/temp-gravity && cd ~/temp-gravity

# 初始化 Git repository
git init
git config user.name "gravity"
git config user.email "gravity@example.com"
git checkout -b master

# 創建初始檔案
echo "# Gravity Atomic Repository" > README.md
echo "node_modules/" > .gitignore
echo "*.log" >> .gitignore

# 提交並推送
git add .
git commit -m "Initial commit"
git remote add origin http://gravity:<your-token>@<node-ip>:31300/gravity/gravity.git
git push -u origin master

# 清理臨時目錄
cd ~ && rm -rf temp-gravity
```

#### 0.3 更新 ConfigMap 中的 Git 配置
```bash
# 編輯 ConfigMap，更新 GIT_TOKEN
vi 00-lab-configmap.yaml

# 更新以下參數：
# GIT_TOKEN: "your-actual-gitea-access-token"
# GIT_URL: "your-node-ip:31300"
```

### 步驟 1：建立 Gravity Namespace 和基礎配置

```bash
# 建立 Gravity 命名空間
kubectl apply -f namespace.yaml

# 部署 ConfigMap
kubectl apply -f 00-lab-configmap.yaml

# 部署 Secret
kubectl apply -f 01-lab-secret.yaml

# 驗證配置
kubectl -n gravity2-lab get configmap,secret
```

### 步驟 2：部署 NATS 叢集

```bash
# 部署 NATS StatefulSet (3個副本叢集)
kubectl apply -f 10-lab-gravity-nats.yaml

# 監控部署狀態
kubectl -n gravity2-lab get pods -l app=gravity,component=nats -w

# 等待所有 NATS Pod 準備就緒
kubectl -n gravity2-lab wait --for=condition=ready pod --selector=app=gravity,component=nats --timeout=600s

# 驗證 NATS 叢集健康狀態
kubectl -n gravity2-lab exec -t lab-gravity-nats-0 -- /nats server list
kubectl -n gravity2-lab exec -t lab-gravity-nats-0 -- /nats server check connection
```

### 步驟 3：部署 Atomic (Low-Code 處理引擎)

```bash
# 部署 Atomic Deployment
kubectl apply -f 40-lab-atomic.yaml

# 監控部署狀態
kubectl -n gravity2-lab get pods -l app=atomic -w

# 等待 Atomic 準備就緒
kubectl -n gravity2-lab wait --for=condition=ready pod --selector=app=atomic --timeout=300s

# 檢查 Atomic 日誌
kubectl -n gravity2-lab logs deployment/lab-atomic-atomic -c init-lab-atomic-git
kubectl -n gravity2-lab logs deployment/lab-atomic-atomic -c lab-atomic
```

### 步驟 4：部署 Dispatcher (系統管理器)

```bash
# 部署 Dispatcher StatefulSet
kubectl apply -f 20-lab-gravity-dispatcher.yaml

# 監控部署狀態
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

# 監控部署狀態
kubectl -n gravity2-lab get pods -l app=gravity-adapter,component=postgres -w

# 等待 Adapter 準備就緒
kubectl -n gravity2-lab wait --for=condition=ready pod --selector=app=gravity-adapter,component=postgres --timeout=300s

# 檢查 Adapter 日誌
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

# 檢查服務端點
kubectl -n gravity2-lab get endpoints
```

## 🌐 訪問和驗證

### Web 服務訪問

```bash
# 取得節點 IP
kubectl get nodes -o wide

# 服務訪問地址
echo "Gitea: http://<node-ip>:31300"
echo "Atomic: http://<node-ip>:32300"
```

### CLI 連線測試

```bash
# 設定 Gravity CLI 連線參數
export GRAVITY_HOST="lab-gravity-nats"
export GRAVITY_PORT="4222"
export GRAVITY_DOMAIN="default"

# Port Forward 測試（如果在叢集外）
kubectl -n gravity2-lab port-forward svc/lab-gravity-nats 4222:4222 &

# 測試 CLI 連線
gravity-cli product list -s localhost:4222
```

### 資料流測試

```bash
# 在 PostgreSQL 來源資料庫執行測試
INSERT INTO your_table_name (id, name, value) VALUES (1, 'test', 'data');
UPDATE your_table_name SET value = 'updated' WHERE id = 1;
DELETE FROM your_table_name WHERE id = 1;

# 檢查 Adapter 日誌是否捕獲變更
kubectl -n gravity2-lab logs lab-adapter-postgres-0 -f
```

## 🛠️ 常見問題解決

### 問題 1：Atomic Pod Init Container 失敗

**錯誤：** `fatal: Remote branch master not found`

**解決方案：**
1. 確保 Gitea repository 已正確初始化
2. 檢查 ConfigMap 中的 Git 配置是否正確
3. 驗證 Access Token 權限

```bash
# 檢查 repository 是否存在內容
curl -I http://<node-ip>:31300/gravity/gravity

# 重新初始化 repository（如果需要）
# 參考步驟 0.2
```

### 問題 2：Atomic 主容器啟動失敗

**錯誤：** `node-red: command not found`

**解決方案：** 
確保使用正確的 Node-RED 啟動路徑：

```yaml
# 在 40-lab-atomic.yaml 中使用正確的命令
command: ["sh", "-c", "cd /atomic && exec node packages/node_modules/node-red/red.js --userDir /data/atomic --port 1880 --host 0.0.0.0"]
```

### 問題 3：無法訪問 Web 介面

**檢查清單：**
```bash
# 1. 檢查 Pod 狀態
kubectl -n gravity2-lab get pods -l app=atomic
kubectl -n gitea get pods

# 2. 檢查服務配置
kubectl -n gravity2-lab get svc lab-atomic
kubectl -n gitea get svc gitea

# 3. 檢查端點
kubectl -n gravity2-lab get endpoints lab-atomic
kubectl -n gitea get endpoints gitea

# 4. 測試連通性
telnet <node-ip> 32300  # Atomic
telnet <node-ip> 31300  # Gitea
```

### 問題 4：PostgreSQL Adapter 連線失敗

**檢查項目：**
1. PostgreSQL 服務器是否啟用 WAL 日誌
2. 用戶是否有 replication 權限
3. 網路連通性
4. 密碼配置正確性

```bash
# 檢查 Adapter 日誌中的連線錯誤
kubectl -n gravity2-lab logs lab-adapter-postgres-0 | grep -i "error\|connect"
```

## 📝 部署檢查清單

完成以下檢查項目，確保部署成功：

- [ ] **Gitea 部署完成** - 可訪問 `http://<node-ip>:31300`
- [ ] **Gitea Repository 初始化** - gravity/gravity.git 存在且有內容
- [ ] **Access Token 生成** - 並更新到 ConfigMap
- [ ] **NATS 叢集運行** - 3個 Pod 全部 Ready
- [ ] **Atomic 部署成功** - 可訪問 `http://<node-ip>:32300`
- [ ] **Dispatcher 運行正常** - Pod 狀態 Running
- [ ] **PostgreSQL Adapter 運行** - 連線到來源資料庫成功
- [ ] **所有服務網路互通** - 端點檢查通過
- [ ] **資料流測試通過** - 能捕獲資料庫變更

## 🔧 維護和監控

### 定期檢查命令
```bash
# 檢查所有 Pod 健康狀態
kubectl -n gravity2-lab get pods
kubectl -n gitea get pods

# 檢查資源使用情況
kubectl -n gravity2-lab top pods

# 檢查 NATS 叢集狀態
kubectl -n gravity2-lab exec -t lab-gravity-nats-0 -- /nats server list

# 備份重要配置
kubectl -n gravity2-lab get configmap labcm -o yaml > backup-configmap.yaml
kubectl -n gravity2-lab get secret labsecret -o yaml > backup-secret.yaml
```

---

**部署完成後，您的 Gravity 2.0 PostgreSQL 版本系統應該能夠正常運行，包含完整的資料捕獲、處理和管理功能。**

## 📞 支援資訊

如遇問題，請檢查：
1. 所有 Pod 日誌
2. 網路連通性
3. 配置檔案正確性
4. 資料庫權限設定