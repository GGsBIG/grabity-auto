# Gravity 2.0 故障排除指南

## 🚨 常見部署問題與解決方案

### 1. 映像拉取失敗 (ErrImagePull)

#### 問題描述
```
Failed to pull image "busybox:50aa4698fa62": not found
```

#### 解決方案
已修正所有 init container 使用的 busybox 版本：
```bash
# 原有的錯誤版本
image: busybox:50aa4698fa62

# 修正後的版本  
image: busybox:1.36
```

#### 驗證方法
```bash
# 檢查是否還有舊版本映像
grep -r "busybox:50aa4698fa62" *.yaml

# 應該沒有結果，如果有請手動替換
sed -i 's/busybox:50aa4698fa62/busybox:1.36/g' *.yaml
```

### 2. PVC 無法綁定 (PersistentVolumeClaims)

#### 問題描述
```
0/5 nodes are available: pod has unbound immediate PersistentVolumeClaims
```

#### 原因分析
- Storage Class 不存在或不可用
- 沒有可用的 PersistentVolume
- 存儲資源不足

#### 解決方案

**步驟 1：檢查 Storage Class**
```bash
# 執行檢查腳本
./check-storageclass.sh

# 或手動檢查
kubectl get storageclass
```

**步驟 2：根據環境選擇 Storage Class**

**選項 A：使用 local-path (推薦)**
```bash
# 如果沒有安裝，先安裝 local-path-provisioner
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml

# 更新配置檔
sed -i 's/#storageClassName: .*/storageClassName: "local-path"/' *.yaml
```

**選項 B：使用預設 Storage Class**
```bash
# 找出預設 Storage Class
kubectl get storageclass | grep "(default)"

# 註解掉 storageClassName 讓 k8s 使用預設
sed -i 's/storageClassName: .*/#storageClassName: "default"/' *.yaml
```

**選項 C：使用特定 Storage Class**
```bash
# 替換為您環境中可用的 Storage Class
sed -i 's/storageClassName: "local-path"/storageClassName: "your-storage-class"/' *.yaml
```

#### 驗證方法
```bash
# 檢查 PVC 狀態
kubectl -n gravity2-lab get pvc

# 檢查 PV 狀態
kubectl get pv
```

### 3. Init Container 等待超時

#### 問題描述
Init container 一直等待 NATS 服務，但 NATS 本身無法啟動

#### 解決方案
採用分階段部署：

```bash
# 使用修正版部署腳本
./deploy-fixed.sh

# 或手動分階段部署
kubectl apply -f namespace.yaml
kubectl apply -f 00-lab-configmap.yaml -f 01-lab-secret.yaml

# 先部署 NATS，等待完全就緒
kubectl apply -f 10-lab-gravity-nats.yaml
kubectl -n gravity2-lab wait --for=condition=ready pod --selector=app=gravity,component=nats --timeout=600s

# 再部署其他服務
kubectl apply -f 20-lab-gravity-dispatcher.yaml
# ... 依此類推
```

### 4. NATS 叢集啟動問題

#### 問題描述
NATS StatefulSet 中的 Pod 無法啟動或連線失敗

#### 常見原因
- DNS 解析問題
- 網路策略限制
- 資源不足

#### 解決方案

**檢查 DNS 解析**
```bash
# 檢查 DNS 服務
kubectl -n kube-system get pods | grep coredns

# 測試內部 DNS
kubectl run -it --rm debug --image=busybox:1.36 --restart=Never -- nslookup lab-gravity-nats-mgmt.gravity2-lab.svc.cluster.local
```

**檢查資源使用**
```bash
# 檢查節點資源
kubectl top nodes

# 檢查 Pod 資源限制
kubectl -n gravity2-lab describe pod lab-gravity-nats-0
```

**降低資源需求（如果必要）**
```yaml
# 修改 10-lab-gravity-nats.yaml
resources:
  limits:
    cpu: "2"      # 從 4 降到 2
    memory: 2Gi   # 從 4Gi 降到 2Gi
  requests:
    cpu: 50m      # 從 100m 降到 50m
    memory: 50Mi  # 從 100Mi 降到 50Mi
```

### 5. Dispatcher 連線 NATS 失敗

#### 問題描述
Dispatcher 無法連線到 NATS 服務

#### 解決方案

**檢查服務發現**
```bash
# 檢查 NATS 服務
kubectl -n gravity2-lab get svc lab-gravity-nats

# 檢查端點
kubectl -n gravity2-lab get endpoints lab-gravity-nats
```

**測試連線**
```bash
# 進入 Dispatcher Pod 測試
kubectl -n gravity2-lab exec -it lab-gravity-dispatcher-0 -- sh
# 在 Pod 內執行
nc -z lab-gravity-nats 4222
```

### 6. Atomic Git 同步失敗

#### 問題描述
Atomic init container 無法從 Gitea 拉取代碼

#### 解決方案

**檢查 Git 配置**
```bash
# 檢查 ConfigMap 中的 Git 設定
kubectl -n gravity2-lab get configmap labcm -o yaml | grep -A 10 GIT
```

**更新 Git Token**
```bash
# 替換為有效的 Token
kubectl -n gravity2-lab patch configmap labcm --patch='{"data":{"GIT_TOKEN":"your-new-token"}}'
```

**測試 Git 連線**
```bash
# 手動測試 Git 連線
git clone http://demo:your-token@your-gitea-url/demo/gravity2-lab.git
```

## 🔧 故障排除工具

### 快速診斷腳本
```bash
# 執行故障排除模式
./deploy-fixed.sh troubleshoot
```

### 手動檢查命令
```bash
# 檢查所有資源狀態
kubectl -n gravity2-lab get all

# 檢查事件
kubectl -n gravity2-lab get events --sort-by='.lastTimestamp'

# 檢查各服務日誌
kubectl -n gravity2-lab logs -l app=gravity,component=nats
kubectl -n gravity2-lab logs -l app=gravity,component=dispatcher
kubectl -n gravity2-lab logs -l app=gravity-adapter
kubectl -n gravity2-lab logs -l app=atomic
```

### 清理重新部署
```bash
# 完全清理
./deploy-fixed.sh cleanup

# 或手動清理
kubectl delete namespace gravity2-lab
kubectl get pv | grep gravity2-lab | awk '{print $1}' | xargs kubectl delete pv
```

## 📋 部署檢查清單

### 部署前檢查
- [ ] Kubernetes 叢集運行正常
- [ ] kubectl 可以連線叢集
- [ ] 有可用的 Storage Class
- [ ] 網路連通性正常
- [ ] 映像可以拉取

### 部署後驗證
- [ ] 所有 Pod 狀態為 Running
- [ ] 所有 PVC 已綁定
- [ ] NATS 叢集正常運行
- [ ] Dispatcher 可以連線 NATS
- [ ] Adapter 可以連線資料庫
- [ ] Atomic 介面可以存取

### 功能測試
- [ ] 可以建立 Data Product
- [ ] 可以設定 RuleSet
- [ ] 資料流正常運行
- [ ] 監控日誌無錯誤

## 🆘 緊急恢復

如果部署完全失敗，使用以下步驟重新開始：

```bash
# 1. 完全清理
kubectl delete namespace gravity2-lab --force --grace-period=0

# 2. 清理殘留 PV
kubectl get pv | grep gravity2-lab | awk '{print $1}' | xargs kubectl delete pv

# 3. 等待清理完成
while kubectl get namespace gravity2-lab &>/dev/null; do sleep 1; done

# 4. 檢查環境
./check-storageclass.sh

# 5. 重新部署
./deploy-fixed.sh deploy
```

---

💡 **提示**：如果問題仍然存在，請檢查 Kubernetes 叢集的基本組件（CoreDNS、網路插件等）是否正常運行。