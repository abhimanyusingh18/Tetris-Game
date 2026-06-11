#!/bin/bash
set -e

echo "Cleaning up AWS Load Balancer Controller..."
kubectl delete deployment aws-load-balancer-controller -n kube-system --ignore-not-found
kubectl delete serviceaccount aws-load-balancer-controller -n kube-system --ignore-not-found
kubectl delete clusterrole aws-load-balancer-controller-role --ignore-not-found
kubectl delete clusterrolebinding aws-load-balancer-controller-rolebinding --ignore-not-found
kubectl delete mutatingwebhookconfiguration aws-load-balancer-webhook --ignore-not-found
kubectl delete validatingwebhookconfiguration aws-load-balancer-webhook --ignore-not-found
kubectl delete secret -n kube-system -l owner=helm,name=aws-load-balancer-controller --ignore-not-found
kubectl delete secret aws-load-balancer-tls -n kube-system --ignore-not-found

echo "Cleaning up ArgoCD..."
kubectl delete secret -n argocd -l owner=helm,name=argocd --ignore-not-found
kubectl delete namespace argocd --ignore-not-found &

sleep 5

echo "Force clearing finalizers on argocd namespace if it is stuck..."
kubectl get namespace argocd -o json | jq '.spec.finalizers=[]' | kubectl replace --raw /api/v1/namespaces/argocd/finalize -f - || true

echo "Cleanup complete!"
