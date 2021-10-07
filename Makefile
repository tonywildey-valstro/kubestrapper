BKPR_VERSION=v1.7.1

# AWS-EKS-specific vars
AWS_EKS_K8S_VERSION=1.17
AWS_EKS_USER=********
AWS_COGNITO_USER_POOL_ID=*****


LOCAL_BIN := $(CURDIR)/.bin
PATH := $(LOCAL_BIN):$(PATH)
export PATH

CURL ?= /usr/bin/curl

EKSCTL := /usr/local/bin/eksctl
$(EKSCTL):
	@brew install eksctl

KUBEPROD := $(LOCAL_BIN)/kubeprod
$(KUBEPROD): $(CURL)
	$(CURL) -LO https://github.com/bitnami/kube-prod-runtime/releases/download/${BKPR_VERSION}/bkpr-${BKPR_VERSION}-darwin-amd64.tar.gz \
	&& tar xf bkpr-${BKPR_VERSION}-darwin-amd64.tar.gz \
	&& chmod +x bkpr-${BKPR_VERSION}/kubeprod \
	&& sudo mv bkpr-${BKPR_VERSION}/kubeprod $(LOCAL_BIN)

KUBECFG := /usr/local/bin/kubecfg
$(KUBECFG): 
	@brew install kubecfg

KUBECTL := /usr/local/bin/kubectl
$(KUBECTL): 
	@brew install kubernetes-cli
	
HELM := /usr/local/bin/helm
$(HELM):
	brew install helm

YTT_RELEASES := https://github.com/k14s/ytt/releases
YTT_VERSION := 0.30.0
YTT_BIN := ytt-$(YTT_VERSION)-darwin-amd64
YTT_URL := https://github.com/k14s/ytt/releases/download/v$(YTT_VERSION)/ytt-darwin-amd64
YTT := $(LOCAL_BIN)/$(YTT_BIN)
$(YTT): $(CURL)
	mkdir -p $(LOCAL_BIN) \
	&& cd $(LOCAL_BIN) \
	&& $(CURL) --progress-bar --fail --location --output $(YTT) "$(YTT_URL)" \
	&& touch $(YTT) \
	&& chmod +x $(YTT) \
	&& $(YTT) version \
	   | grep $(YTT_VERSION) \
	&& ln -sf $(YTT) $(LOCAL_BIN)/ytt
.PHONY: ytt
ytt: $(YTT)
.PHONY: releases-ytt
releases-ytt:
	@$(OPEN) $(YTT_RELEASES)

AWS_EKS_CLUSTER_SPEC=$(CURDIR)/.out/cluster.yml

.PHONY: cluster-create
cluster-create: $(EKSCTL) $(YTT)
	cat $(CURDIR)/cluster.yml | \
	sed "s/#CLUSTER_NAME#/$(CLUSTER_NAME)/g" > $(AWS_EKS_CLUSTER_SPEC) \
	&& $(EKSCTL) create cluster -f $(AWS_EKS_CLUSTER_SPEC)

.PHONY: cluster-delete
cluster-delete: $(EKSCTL) $(YTT)
	cat $(CURDIR)/cluster.yml | \
	sed "s/#CLUSTER_NAME#/$(CLUSTER_NAME)/g" > $(AWS_EKS_CLUSTER_SPEC) \
	&& $(EKSCTL) delete cluster -f $(AWS_EKS_CLUSTER_SPEC)

.PHONY: validate
validate:
ifeq (,$(CLUSTER_NAME))
	$(error pass a CLUSTER_NAME)
endif
ifeq (,$(DNS_ZONE))
	$(error pass a DNS_ZONE)
endif

.PHONY: runtime-deploy
runtime-deploy: $(KUBEPROD) validate
	cp ./kubeprod-autogen.${ENVIRONMENT}.json ./kubeprod-autogen.json \
	&& $(KUBEPROD) install eks \
		--email ${AWS_EKS_USER} \
		--dns-zone "${DNS_ZONE}" \
		--user-pool-id "${AWS_COGNITO_USER_POOL_ID}" \
  && $(HELM) upgrade metrics-server \
    --install stable/metrics-server \
    --namespace kubeprod \
	&& $(HELM) repo add autoscaler https://kubernetes.github.io/autoscaler \
	&& $(HELM) upgrade cluster-autoscaler --install autoscaler/cluster-autoscaler-chart \
		--set autoDiscovery.clusterName=$(CLUSTER_NAME) \
		--namespace kubeprod \
	&& rm ./kubeprod-autogen.json

.PHONY: runtime-scaledown-logging	 
runtime-scaledown-logging: $(KUBECTL)
	$(KUBECTL) scale --replicas=0 --namespace kubeprod deployment/kibana \
	&& $(KUBECTL) scale --replicas=0 --namespace kubeprod statefulset/elasticsearch-logging \

.PHONY: runtime-delete
runtime-delete: $(KUBEPROD) $(KUBECFG) validate 
	cp ./kubeprod-autogen.${ENVIRONMENT}.json ./kubeprod-autogen.json \
	&& $(KUBECFG) delete kubeprod-manifest.jsonnet \
	&& $(KUBECTL) wait --for=delete ns/kubeprod --timeout=300s

