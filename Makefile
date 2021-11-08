BKPR_VERSION=v1.8.1
KUBEPROD_RELEASE_URL=https://github.com/andycmaj/kube-prod-runtime/releases/download
# KUBEPROD_RELEASE_URL=https://github.com/bitnami/kube-prod-runtime/releases/download

LOCAL_BIN := $(CURDIR)/.bin
PATH := $(LOCAL_BIN):$(PATH)
export PATH

OS = $(shell uname -s | awk '{print tolower($0)}')

CURL ?= $(shell which curl)

EKSCTL := $(shell which eksctl)
$(EKSCTL):
	@brew install eksctl

KUBEPROD := $(LOCAL_BIN)/kubeprod
$(KUBEPROD): $(CURL)
	$(CURL) -LO ${KUBEPROD_RELEASE_URL}/${BKPR_VERSION}/bkpr-${BKPR_VERSION}-${OS}-amd64.tar.gz \
	&& tar xf bkpr-${BKPR_VERSION}-${OS}-amd64.tar.gz \
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
YTT_BIN := ytt-$(YTT_VERSION)-${OS}-amd64
YTT_URL := https://github.com/k14s/ytt/releases/download/v$(YTT_VERSION)/ytt-${OS}-amd64
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

CLUSTER_REGION ?= "us-east-2"
CLUSTER_VERSION ?= "1.21"
AWS_EKS_CLUSTER_SPEC=$(CURDIR)/.out/cluster.yml

.PHONY: cluster-create
cluster-create: $(EKSCTL) $(YTT)
	cat $(CURDIR)/cluster.yml | \
	sed "s/#CLUSTER_NAME#/$(CLUSTER_NAME)/g" | \
	sed "s/#CLUSTER_REGION#/$(CLUSTER_REGION)/g" | \
	sed "s/#CLUSTER_VERSION#/\"$(CLUSTER_VERSION)\"/g" > $(AWS_EKS_CLUSTER_SPEC) \
	&& $(EKSCTL) create cluster -f $(AWS_EKS_CLUSTER_SPEC)

.PHONY: cluster-delete
cluster-delete: $(EKSCTL) $(YTT)
	cat $(CURDIR)/cluster.yml | \
	sed "s/#CLUSTER_NAME#/$(CLUSTER_NAME)/g" | \
	sed "s/#CLUSTER_REGION#/$(CLUSTER_REGION)/g" | \
	sed "s/#CLUSTER_VERSION#/\"$(CLUSTER_VERSION)\"/g" > $(AWS_EKS_CLUSTER_SPEC) \
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
runtime-deploy: $(KUBEPROD) $(HELM) validate
	[ -e "./kubeprod-autogen.${ENVIRONMENT}.json" ] && cp ./kubeprod-autogen.${ENVIRONMENT}.json ./kubeprod-autogen.json || echo "no autogen exists yet" \
	&& $(KUBEPROD) install eks \
		--email ${AWS_EKS_USER} \
		--dns-zone "${DNS_ZONE}" \
		--authz-domain "${AUTHZ_DOMAIN}" \
		--keycloak-password "${KEYCLOAK_PASSWORD}" \
		--keycloak-group "${KEYCLOAK_GROUP}" \
		--manifests ./bkpr-${BKPR_VERSION}/manifests \
	&& $(HELM) repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ \
	&& $(HELM) upgrade metrics-server --install metrics-server/metrics-server \
		--namespace kubeprod \
	&& $(HELM) repo add autoscaler https://kubernetes.github.io/autoscaler \
	&& $(HELM) upgrade cluster-autoscaler --install autoscaler/cluster-autoscaler-chart \
		--set autoDiscovery.clusterName=$(CLUSTER_NAME) \
		--namespace kubeprod \
	&& mv ./kubeprod-autogen.json ./kubeprod-autogen.${ENVIRONMENT}.json

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

