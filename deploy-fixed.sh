#!/bin/bash

echo "=== Gravity 2.0 修正版部署腳本 ==="

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 檢查函數
check_pod_status() {
    local selector=$1
    local timeout=${2:-300}
    local namespace="gravity2-lab"
    
    echo -n "等待 Pod 就緒 ($selector)..."
    if kubectl -n $namespace wait --for=condition=ready pod --selector=$selector --timeout=${timeout}s; then
        echo -e "${GREEN}✓ 就緒${NC}"
        return 0
    else
        echo -e "${RED}✗ 超時或失敗${NC}"
        echo "檢查 Pod 狀態:"
        kubectl -n $namespace get pods --selector=$selector
        echo "檢查 Pod 詳細資訊:"
        kubectl -n $namespace describe pods --selector=$selector
        return 1
    fi
}

# 清理之前的部署
cleanup_previous() {
    echo "步驟 0: 清理之前的部署..."
    kubectl delete namespace gravity2-lab --ignore-not-found=true
    echo "等待 namespace 完全清理..."
    while kubectl get namespace gravity2-lab &>/dev/null; do
        echo -n "."
        sleep 2
    done
    echo -e "${GREEN}✓ 清理完成${NC}"
}

# 檢查 Storage Class
check_storage_class() {
    echo "檢查 Storage Class..."
    if kubectl get storageclass local-path &>/dev/null; then
        echo -e "${GREEN}✓ local-path Storage Class 存在${NC}"
    elif kubectl get storageclass | grep -q "(default)"; then
        echo -e "${YELLOW}! 使用預設 Storage Class${NC}"
        # 更新配置檔使用預設 Storage Class
        sed -i 's/storageClassName: "local-path"/#storageClassName: "local-path"/' *.yaml
    else
        echo -e "${RED}✗ 沒有可用的 Storage Class${NC}"
        echo "可用的 Storage Classes:"
        kubectl get storageclass
        exit 1
    fi
}

# 檢查必要映像
check_images() {
    echo "檢查映像可用性..."
    images=(
        "ghcr.io/brobridgeorg/nats-server:v1.3.25-20250701"
        "ghcr.io/brobridgeorg/gravity-dispatcher:v0.0.31-20250701"
        "ghcr.io/brobridgeorg/atomic/atomic:v0.0.5-20231012-ubi"
        "busybox:1.36"
    )
    
    for image in "${images[@]}"; do
        echo -n "檢查映像 $image..."
        if docker pull $image &>/dev/null || crictl pull $image &>/dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${YELLOW}! 可能無法拉取，但繼續部署${NC}"
        fi
    done
}

# 主要部署流程
main_deploy() {
    # 清理之前的部署
    read -p "是否要清理之前的部署? (y/N): " cleanup
    if [[ $cleanup =~ ^[Yy]$ ]]; then
        cleanup_previous
    fi

    # 檢查環境
    check_storage_class
    check_images

    # 1. 建立 namespace
    echo "步驟 1: 建立 namespace..."
    kubectl apply -f namespace.yaml
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Namespace 建立成功${NC}"
    else
        echo -e "${RED}✗ Namespace 建立失敗${NC}"
        exit 1
    fi

    # 2. 配置 Configmap & Secret
    echo "步驟 2: 配置 Configmap 和 Secret..."
    kubectl apply -f 00-lab-configmap.yaml
    kubectl apply -f 01-lab-secret.yaml
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 配置檔套用成功${NC}"
    else
        echo -e "${RED}✗ 配置檔套用失敗${NC}"
        exit 1
    fi

    # 3. 部署 NATS
    echo "步驟 3: 部署 NATS 叢集..."
    kubectl apply -f 10-lab-gravity-nats.yaml
    
    # 等待 NATS 就緒
    if ! check_pod_status "app=gravity,component=nats" 600; then
        echo -e "${RED}NATS 部署失敗，檢查 PVC 狀態:${NC}"
        kubectl -n gravity2-lab get pvc
        kubectl -n gravity2-lab describe pvc
        exit 1
    fi

    # 4. 部署 Dispatcher
    echo "步驟 4: 部署 Dispatcher..."
    kubectl apply -f 20-lab-gravity-dispatcher.yaml

    # 等待 Dispatcher 就緒
    if ! check_pod_status "app=gravity,component=dispatcher" 300; then
        echo -e "${RED}Dispatcher 部署失敗${NC}"
        exit 1
    fi

    # 5. 部署 Adapter (讓用戶選擇)
    echo "步驟 5: 選擇要部署的 Adapter..."
    echo "1) MSSQL Adapter"
    echo "2) PostgreSQL Adapter"
    echo "3) 都不部署"
    read -p "請選擇 (1-3): " adapter_choice

    case $adapter_choice in
        1)
            echo "部署 MSSQL Adapter..."
            kubectl apply -f 30-lab-adapter-mssql.yaml
            check_pod_status "app=gravity-adapter,component=mssql" 300
            ;;
        2)
            echo "部署 PostgreSQL Adapter..."
            kubectl apply -f 30-lab-adapter-postgres.yaml
            check_pod_status "app=gravity-adapter,component=postgres" 300
            ;;
        3)
            echo "跳過 Adapter 部署"
            ;;
        *)
            echo -e "${YELLOW}無效選擇，跳過 Adapter 部署${NC}"
            ;;
    esac

    # 6. 部署 Atomic
    echo "步驟 6: 部署 Atomic..."
    kubectl apply -f 40-lab-atomic.yaml

    # 等待 Atomic 就緒
    if ! check_pod_status "app=atomic" 300; then
        echo -e "${RED}Atomic 部署失敗${NC}"
        exit 1
    fi

    echo -e "${GREEN}=== 部署完成 ===${NC}"
    echo ""
    echo "檢查部署狀態:"
    kubectl -n gravity2-lab get pods -o wide
    echo ""
    echo "檢查服務:"
    kubectl -n gravity2-lab get svc
    echo ""
    echo -e "${GREEN}Atomic 介面可透過 NodePort 32300 存取${NC}"
    
    # 取得 NodePort 存取資訊
    node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    echo -e "${GREEN}存取 URL: http://$node_ip:32300${NC}"
}

# 故障排除模式
troubleshoot() {
    echo "=== 故障排除模式 ==="
    echo ""
    echo "1. 檢查所有 Pod 狀態"
    kubectl -n gravity2-lab get pods -o wide
    echo ""
    
    echo "2. 檢查 PVC 狀態"
    kubectl -n gravity2-lab get pvc
    echo ""
    
    echo "3. 檢查有問題的 Pod"
    failed_pods=$(kubectl -n gravity2-lab get pods --field-selector=status.phase!=Running --no-headers 2>/dev/null | awk '{print $1}')
    
    if [ -n "$failed_pods" ]; then
        for pod in $failed_pods; do
            echo -e "${RED}問題 Pod: $pod${NC}"
            kubectl -n gravity2-lab describe pod $pod
            echo "---"
        done
    else
        echo -e "${GREEN}所有 Pod 運行正常${NC}"
    fi
    
    echo ""
    echo "4. 檢查映像拉取問題"
    kubectl -n gravity2-lab get events --sort-by='.lastTimestamp' | grep -i "image\|pull"
}

# 主選單
case "${1:-deploy}" in
    "deploy")
        main_deploy
        ;;
    "troubleshoot")
        troubleshoot
        ;;
    "cleanup")
        cleanup_previous
        ;;
    *)
        echo "用法: $0 [deploy|troubleshoot|cleanup]"
        echo "  deploy      - 執行完整部署 (預設)"
        echo "  troubleshoot - 故障排除模式"
        echo "  cleanup     - 清理部署"
        exit 1
        ;;
esac