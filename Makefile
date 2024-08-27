export GIT_REPO := https://github.com/JacekZubielik/dev-k3s-lab-autopilot.git

all:

.PHONY: kubeconfig sops autopilot login-argocd password-argocd password-grafana help

deploy-all:sops autopilot password-argocd help

kubeconfig: ## Copy 'kubeconfig'.
	@echo "\nCopy kubeconfig to ~/.kube/ ...\n"
	@scp vagrant@192.168.40.200:~/.kube/config ~/.kube/config
	@kubectl get nodes --show-kind

sops: ## Import a sops AGE and PGP secret keys.
	@echo "\nImport a sops AGE and PGP secret keys ...\n"
	@kubectl create namespace argocd --dry-run=client --output=yaml \
			| kubectl apply -f -
	@cat ~/.config/sops/age/keys.txt | kubectl create secret generic sops-age --namespace=argocd --from-file=keys.txt=/dev/stdin
	@gpg --export-secret-keys --armor "${SOPS_PGP_FP}" | kubectl create secret generic sops-gpg --namespace=argocd --from-file=sops.asc=/dev/stdin

autopilot: ## Deploy Argo CD autopilot recovery on Kubernetes cluster.
	@echo "\nDeploy Argo CD autopilot on Kubernetes cluster ...\n"
	@argocd-autopilot repo bootstrap --recover --app "${GIT_REPO}/bootstrap/argo-cd"
	@kubectl -n argocd wait --for=condition=available --timeout=600s --all deployments

password-argocd: ## Show admin password for ArgoCD.
	@echo "\nAdmin password for ArgoCD:\n"
	@kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

password-grafana: ## Show admin password for Grafana.
	@echo "\nAdmin password for Grafana:\n"
	@kubectl get secrets -n monitoring kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d

login-argocd: ## Login to ArgoCD CLI.
	@echo "\nLogin to ArgoCD CLI ...\n"
	@argocd login 192.168.40.182 --insecure --username admin --password $$(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

help: ## Display this help.
	@echo "\nDisplay this help ..."
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
