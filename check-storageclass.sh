#!/bin/bash

echo "=== Storage Class 檢查工具 ==="
echo ""

# 檢查可用的 Storage Classes
echo "1. 檢查可用的 Storage Classes:"
kubectl get storageclass

echo ""
echo "2. 檢查預設 Storage Class:"
default_sc=$(kubectl get storageclass | grep "(default)" | awk '{print $1}')
if [ -n "$default_sc" ]; then
    echo "預設 Storage Class: $default_sc"
else
    echo "沒有設定預設 Storage Class"
fi

echo ""
echo "3. 建議的 Storage Class 配置:"
if kubectl get storageclass local-path &>/dev/null; then
    echo "✓ 可以使用 local-path"
    echo "在 YAML 檔案中使用: storageClassName: \"local-path\""
elif [ -n "$default_sc" ]; then
    echo "✓ 可以使用預設 Storage Class: $default_sc" 
    echo "在 YAML 檔案中移除或註解: #storageClassName: \"...\""
else
    echo "⚠ 需要安裝 Storage Class 提供者"
    echo ""
    echo "可以安裝 local-path-provisioner:"
    echo "kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml"
fi

echo ""
echo "4. 更新部署檔案的 Storage Class:"
echo "執行以下命令來更新所有 YAML 檔案:"

if kubectl get storageclass local-path &>/dev/null; then
    echo "sed -i 's/#storageClassName: .*/storageClassName: \"local-path\"/' *.yaml"
elif [ -n "$default_sc" ]; then
    echo "sed -i 's/storageClassName: .*/#storageClassName: \"$default_sc\"/' *.yaml"
else
    echo "需要先安裝 Storage Class 提供者"
fi