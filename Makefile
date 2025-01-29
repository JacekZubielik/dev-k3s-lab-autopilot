export GIT_REPO 		:= https://github.com/JacekZubielik/dev-k3s-lab-autopilot.git
export KUBECONFIG_IP 	:= 192.168.40.200
export ARGOCD_IP 		:= 192.168.40.182
export ARGOCD_NS 		:= argocd

all:

ifneq ($(DEBUG),y)
.SILENT:
endif

deploy-all: sops autopilot password-argocd help

.PHONY: kubeconfig
kubeconfig: ## Copy 'kubeconfig'.
	echo "\nCopy kubeconfig to ~/.kube/ ...\n"
	scp ansible@$(KUBECONFIG_IP):~/.kube/config ~/.kube/config
	kubectl get nodes --show-kind

.PHONY: sops
sops: ## Import a sops AGE and PGP secret keys.
	echo "\nImport a sops AGE and PGP secret keys ...\n"
	kubectl create namespace $(ARGOCD_NS) --dry-run=client --output=yaml \
		| kubectl apply -f - || (echo "Error: Failed to create namespace"; exit 1)
	cat ~/.config/sops/age/keys.txt | kubectl create secret generic sops-age --namespace=$(ARGOCD_NS) --from-file=keys.txt=/dev/stdin || (echo "Error: Failed to create sops-age secret"; exit 1)
	gpg --export-secret-keys --armor "${SOPS_PGP_FP}" | kubectl create secret generic sops-gpg --namespace=$(ARGOCD_NS) --from-file=sops.asc=/dev/stdin || (echo "Error: Failed to create sops-gpg secret"; exit 1)

.PHONY: autopilot
autopilot: ## Deploy Argo CD autopilot recovery on Kubernetes cluster.
	echo "\nDeploy Argo CD autopilot on Kubernetes cluster ...\n"
	argocd-autopilot repo bootstrap --recover --app "$(GIT_REPO)/bootstrap/argo-cd" || (echo "Error: Argo CD bootstrap failed"; exit 1)
	kubectl -n $(ARGOCD_NS) wait --for=condition=available --timeout=600s deployment/argocd-server || (echo "Error: Argo CD server not ready"; exit 1)

.PHONY: password-argocd
password-argocd: ## Show admin password for ArgoCD.
	echo "\nAdmin password for ArgoCD:\n"
	kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

.PHONY: login-argocd
login-argocd: ## Login to ArgoCD CLI.
	echo "\nLogin to ArgoCD CLI ...\n"
	kubectl get secret -n $(ARGOCD_NS) argocd-initial-admin-secret > /dev/null 2>&1 || (echo "Error: ArgoCD admin secret not found"; exit 1)
	argocd login $(ARGOCD_IP) --insecure --username admin --password $$(kubectl get secret -n $(ARGOCD_NS) argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

.PHONY: help
help: ## Display this help.
	echo "\nDisplay this help ..."
	awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
