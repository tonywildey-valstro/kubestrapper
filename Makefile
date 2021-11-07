BKPR_VERSION=v1.8.0

# AWS-EKS-specific vars
AWS_EKS_K8S_VERSION=1.21
AWS_EKS_USER=andycunningham@valstro.com
AWS_COGNITO_USER_POOL_ID=us-east-2_3CrvM464c

LOCAL_BIN := $(CURDIR)/.bin
PATH := $(LOCAL_BIN):$(PATH)
export PATH

CURL ?= /usr/bin/curl

EKSCTL := $(shell which eksctl)
$(EKSCTL):
	@brew install eksctl

KUBEPROD := $(LOCAL_BIN)/kubeprod
$(KUBEPROD): $(CURL)
	$(CURL) -LO https://github.com/bitnami/kube-prod-runtime/releases/download/${BKPR_VERSION}/bkpr-${BKPR_VERSION}-linux-amd64.tar.gz \
	&& tar xf bkpr-${BKPR_VERSION}-linux-amd64.tar.gz \
	&& chmod +x bkpr-${BKPR_VERSION}/kubeprod \
	&& sudo mv bkpr-${BKPR_VERSION}/kubeprod $(LOCAL_BIN)

KUBECFG := $(shell which kubecfg)
$(KUBECFG): 
	@brew install kubecfg

KUBECTL := $(shell which kubectl)
$(KUBECTL): 
	@brew install kubernetes-cli
	
HELM := $(shell which helm)
$(HELM):
	@brew install helm

YTT_RELEASES := https://github.com/k14s/ytt/releases
YTT_VERSION := 0.30.0
YTT_BIN := ytt-$(YTT_VERSION)-windows-amd64.exe
YTT_URL := https://github.com/vmware-tanzu/carvel-ytt/releases/download/v$(YTT_VERSION)/ytt-windows-amd64.exe
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

# cp ./kubeprod-autogen.${ENVIRONMENT}.json ./kubeprod-autogen.json \

.PHONY: runtime-deploy
runtime-deploy: $(KUBEPROD) $(HELM) validate
	$(KUBEPROD) install eks \
		--email ${AWS_EKS_USER} \
		--dns-zone "${DNS_ZONE}" \
		--user-pool-id "${AWS_COGNITO_USER_POOL_ID}" \
   	&& $(HELM) repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ \
  	&& $(HELM) upgrade metrics-server --install metrics-server/metrics-server --namespace kubeprod \
	&& $(HELM) repo add autoscaler https://kubernetes.github.io/autoscaler \
	&& $(HELM) upgrade cluster-autoscaler --install autoscaler/cluster-autoscaler-chart \
		--set autoDiscovery.clusterName=$(CLUSTER_NAME) \
		--namespace kubeprod

.PHONY: runtime-test-deploy
runtime-test-deploy: $(HELM) 
	$(HELM) upgrade test-webapp --install ./test/test-webapp \
		--set domain=${TEST_APP_DOMAIN}

.PHONY: runtime-scaledown-logging	 
runtime-scaledown-logging: $(KUBECTL)
	$(KUBECTL) scale --replicas=0 --namespace kubeprod deployment/kibana \
	&& $(KUBECTL) scale --replicas=0 --namespace kubeprod statefulset/elasticsearch-logging \

.PHONY: runtime-delete
runtime-delete: $(KUBEPROD) $(KUBECFG) validate 
	cp ./kubeprod-autogen.${ENVIRONMENT}.json ./kubeprod-autogen.json \
	&& $(KUBECFG) delete kubeprod-manifest.jsonnet \
	&& $(KUBECTL) wait --for=delete ns/kubeprod --timeout=300s

