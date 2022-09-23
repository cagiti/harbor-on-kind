CS := \033[92m
CE := \033[0m

# Values
CLUSTER_NAME := harbor-cluster

# Commands and Environment Variables
DOCKER_CONTENT_TRUST := DOCKER_CONTENT_TRUST=0
KIND_CONFIG := kind-config.yaml

kind:
ifeq (, $(shell which kind 2> /dev/null))
	$(error kind not found. Please install it: https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
KIND=kind-not-found
else
KIND=$(shell which kind 2>/dev/null)
KIND_WIH_EXPORTS := $(DOCKER_CONTENT_TRUST) $(KIND)
endif

helm:
ifeq (, $(shell which helm 2>/dev/null))
	$(error Helm not found. Please install it: https://helm.sh/docs/intro/install/#from-script)
HELM=helm-not-found
else
HELM=$(shell which helm 2>/dev/null)
endif

kustomize:
ifeq (, $(shell which kustomize 2>/dev/null))
	$(error kustomize not found. Please install it: https://kubectl.docs.kubernetes.io/installation/kustomize/)
KUSTOMIZE=kustomize-not-found
else
KUSTOMIZE=$(shell which kustomize 2>/dev/null)
endif

check-context:
	@if [ "$(shell kubectl config view -o json --minify 2>/dev/null | jq -r '.contexts[].context.cluster')" != "kind-$(CLUSTER_NAME)" ]; then \
		echo "Current context is not pointing to $(CS)$(CLUSTER_NAME)$(CE). Please change your kube context to target the correct cluster." && exit 3; \
	else \
		echo "Currently connected to $(CS)$(CLUSTER_NAME)$(CE) in the $(CS)$(env)$(CE) environment"; \
	fi

kind-cluster: kind
	@if [ $(shell $(KIND) get clusters | grep -c $(CLUSTER_NAME)) -eq 0 ]; then \
		$(KIND_WIH_EXPORTS) create cluster --name $(CLUSTER_NAME) --config $(KIND_CONFIG); \
	fi

rm-kind-cluster: kind
	@if [ $(shell $(KIND) get clusters | grep -c $(CLUSTER_NAME)) -eq 1 ]; then \
		$(KIND) delete cluster --name $(CLUSTER_NAME); \
	fi

install-cert-manager: check-context helm
	$(HELM) repo add jetstack https://charts.jetstack.io; \
	$(HELM) repo update; \
	$(HELM) install \
	  cert-manager jetstack/cert-manager \
	  --namespace cert-manager \
	  --create-namespace \
	  --version v1.9.1 \
	  --set installCRDs=true; \
	kubectl -n cert-manager wait --for=condition=available --timeout=240s deployment --all;

install-nginx: check-context
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml; \
	kubectl -n ingress-nginx wait --for=condition=available --timeout=240s deployment --all; \
	kubectl -n ingress-nginx wait --for=condition=PodScheduled --timeout=240s pod --all; \
	kubectl annotate ingressClass nginx ingressclass.kubernetes.io/is-default-class=true --overwrite

install-harbor-operator: check-context
	kubectl apply -f https://raw.githubusercontent.com/goharbor/harbor-operator/v1.3.0/manifests/cluster/deployment.yaml; \
	kubectl -n harbor-operator-ns wait --for=condition=available --timeout=240s deployment --all; \
	kubectl get all -n harbor-operator-ns

install-fullstack:
	sed 's/EN0_IP_ADDRESS/'$(shell ipconfig getifaddr en0)'/g' test_full_stack.yaml | kubectl create -f -; \
	sleep 2; \
	kubectl -n cluster-sample-ns wait --for=condition=available --timeout=240s deployment --all;

setup: kind-cluster install-cert-manager install-nginx install-harbor-operator install-fullstack
cleanup: check-context rm-kind-cluster
