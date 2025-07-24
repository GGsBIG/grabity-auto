#!/bin/bash

echo "=== Gravity 2.0 部署腳本 ==="

# 1. 建立 namespace
echo "步驟 1: 建立 namespace..."
kubectl apply -f namespace.yaml

# 2. 配置 Configmap & Secret
echo "步驟 2: 配置 Configmap 和 Secret..."
kubectl apply -f 00-lab-configmap.yaml
kubectl apply -f 01-lab-secret.yaml

# 3. 部署 NATS
echo "步驟 3: 部署 NATS 叢集..."
kubectl apply -f 10-lab-gravity-nats.yaml

# 等待 NATS 就緒
echo "等待 NATS 就緒..."
kubectl -n gravity2-lab wait --for=condition=ready pod --selector=app=gravity,component=nats --timeout=300s

# 4. 部署 Dispatcher
echo "步驟 4: 部署 Dispatcher..."
kubectl apply -f 20-lab-gravity-dispatcher.yaml

# 等待 Dispatcher 就緒
echo "等待 Dispatcher 就緒..."
kubectl -n gravity2-lab wait --for=condition=ready pod --selector=app=gravity,component=dispatcher --timeout=300s

# 5. 部署 Adapter
echo "步驟 5: 部署 Adapter..."
kubectl apply -f 30-lab-adapter-mssql.yaml

# 等待 Adapter 就緒
echo "等待 Adapter 就緒..."
kubectl -n gravity2-lab wait --for=condition=ready pod --selector=app=gravity-adapter,component=mssql --timeout=300s

# 6. 部署 Atomic
echo "步驟 6: 部署 Atomic..."
kubectl apply -f 40-lab-atomic.yaml

# 等待 Atomic 就緒
echo "等待 Atomic 就緒..."
kubectl -n gravity2-lab wait --for=condition=ready pod --selector=app=atomic --timeout=300s

echo "=== 部署完成 ==="
echo ""
echo "檢查部署狀態:"
kubectl -n gravity2-lab get pods
echo ""
echo "檢查服務:"
kubectl -n gravity2-lab get svc
echo ""
echo "Atomic 介面可透過 NodePort 32300 存取"