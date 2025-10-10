SHELL:=/bin/bash

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

clone-all: ## Initialize all git submodules
	git -C appcat pull || git clone git@github.com:vshn/appcat || true
	git -C component-appcat pull || git clone git@github.com:vshn/component-appcat || true
	git -C component-spks-crossplane pull || git clone git@git.vshn.net:swisscompks/component-spks-crossplane.git || true
	git -C component-exporter-filterproxy pull || git clone git@github.com:vshn/component-exporter-filterproxy.git || true
	git -C kindev pull || git clone git@github.com:vshn/kindev || true

clean-container: ## Delete all submodules
	rm -rf appcat component-appcat component-spks-crossplane kindev

setup-spks: ## Setup spks kindev environment
	cd kindev && \
	make spks
	cp kindev/.kind/kind-config ~/.kube/config

setup-kindev: ## Setup kindev environment
	cd kindev && \
	make vshnall
	cp kindev/.kind/kind-config ~/.kube/config

clean-kindev: ## Clean kindev
	cd kindev && \
	make clean

push-golden: DEBUG=true
push-golden: HOST=$(shell docker inspect kindev-control-plane | jq '.[0].NetworkSettings.Networks.kind.Gateway')
push-golden: ## Push AppCat configuration converged mode to local forgejo. By default it will try to connect to AppCat running in debug mode. Use `-e DEBUG=false` to run against containers in the cluster
	yq '.parameters.appcat.proxyFunction |= $(DEBUG)' component-appcat/tests/dev.yml | diff -B component-appcat/tests/dev.yml - | patch component-appcat/tests/dev.yml -
	yq '.parameters.appcat.grpcEndpoint |= $(HOST)+":9443"' component-appcat/tests/dev.yml | diff -B component-appcat/tests/dev.yml - | patch component-appcat/tests/dev.yml -
	cd component-appcat && \
	make push-golden && \
	cd .. && \
	$(MAKE) export-cluster-env-single && \
	$(MAKE) patch-keycloak-composition FORGEJO_REPO=gitea_admin/appcat

push-non-converged: DEBUG=true
push-non-converged: ## Push AppCat configuration non-converged mode to local forgejo. By default it will try to connect to AppCat running in debug mode. Use `-e DEBUG=false` to run against containers in the cluster
	yq '.parameters.appcat.proxyFunction |= $(DEBUG)' component-appcat/tests/control-plane.yml | diff -B component-appcat/tests/control-plane.yml - | patch component-appcat/tests/control-plane.yml -
	cd component-appcat && \
	make push-non-converged && \
	cd ../kindev && \
	export serviceCluster=$$(make vcluster-host-kubeconfig | grep -v "Leaving" | grep -v "Entering") && \
	export controlCluster=$$(make vcluster-in-cluster-kubeconfig | grep -v 'make' | grep -v "Entering") && \
	cd .. && \
	yq '.parameters.appcat.clusterManagementSystem.serviceClusterKubeconfigs[0].config |= strenv(serviceCluster)' component-appcat/tests/control-plane.yml | diff -B component-appcat/tests/control-plane.yml - | patch component-appcat/tests/control-plane.yml - && \
	yq '.parameters.appcat.clusterManagementSystem.controlPlaneKubeconfig |= strenv(controlCluster)' component-appcat/tests/service-cluster.yml | diff -B component-appcat/tests/service-cluster.yml - | patch component-appcat/tests/service-cluster.yml - && \
	cd component-appcat && \
	make push-non-converged && \
	cd .. && \
	$(MAKE) export-cluster-env-multi && \
	cp kindev/.kind/vcluster-config ~/.kube/config && \
	$(MAKE) patch-keycloak-composition FORGEJO_REPO=gitea_admin/control-plane

push-spks: DEBUG=true
push-spks:
	yq '.parameters.spks_crossplane.proxyFunction |= $(DEBUG)' component-spks-crossplane/tests/control-plane.yml | diff -B component-spks-crossplane/tests/control-plane.yml - | patch component-spks-crossplane/tests/control-plane.yml -
	cd component-spks-crossplane && \
	make push-non-converged && \
	cd ../kindev && \
	export serviceCluster=$$(make vcluster-host-kubeconfig appcat_namespace=spks-crossplane | grep -v "Leaving" | grep -v "Entering") && \
	export controlCluster=$$(make vcluster-in-cluster-kubeconfig appcat_namespace=spks-crossplane | grep -v 'make' | grep -v "Entering") && \
	cd .. && \
	yq '.parameters.spks_crossplane.clusterManagementSystem.serviceClusterKubeconfigs[0].config |= strenv(serviceCluster)' component-spks-crossplane/tests/control-plane.yml | diff -B component-spks-crossplane/tests/control-plane.yml - | patch component-spks-crossplane/tests/control-plane.yml - && \
	yq '.parameters.spks_crossplane.clusterManagementSystem.controlPlaneKubeconfig |= strenv(controlCluster)' component-spks-crossplane/tests/service-cluster.yml | diff -B component-spks-crossplane/tests/service-cluster.yml - | patch component-spks-crossplane/tests/service-cluster.yml - && \
	cd component-spks-crossplane && \
	make push-non-converged && \
	cd ../component-exporter-filterproxy && \
	make push-non-converged && \
	cd .. && \
	$(MAKE) export-cluster-env-multi && \
	$(MAKE) patch-keycloak-composition FORGEJO_REPO=gitea_admin/control-plane

.PHONY: export-cluster-env-single # Export environment variables for e2e tests in single cluster mode (converged)
export-cluster-env-single:
	@rm -f component-appcat/.env || true
	@cp kindev/.kind/kind-config kindev/.kind/in-cluster-kind-config && \
    	yq -i '.clusters[0].cluster.server = "https://kubernetes.default.svc:443"' kindev/.kind/in-cluster-kind-config
	echo "export IN_CLUSTER_CONTROL_PLANE_KUBECONFIG=../kindev/.kind/in-cluster-kind-config" >> component-appcat/.env; \
	echo "export IN_CLUSTER_SERVICE_CLUSTER_KUBECONFIG=../kindev/.kind/in-cluster-kind-config" >> component-appcat/.env; \
	echo "export CONTROL_PLANE_KUBECONFIG_CONTENT='$$(cat kindev/.kind/kind-config | base64 -w 0)'" >> component-appcat/.env; \
	echo "export SERVICE_CLUSTER_KUBECONFIG_CONTENT='$$(cat kindev/.kind/kind-config | base64 -w 0)'" >> component-appcat/.env; \

.PHONY: export-cluster-env-multi # Export environment variables for e2e tests in multi cluster mode (non-converged)
export-cluster-env-multi:
	@cd kindev && \
	   $(MAKE) --no-print-directory vcluster-host-kubeconfig > .kind/from-control-to-service-kubeconfig && \
	   $(MAKE) --no-print-directory vcluster-in-cluster-kubeconfig > .kind/from-service-to-control-kubeconfig
	@rm -f component-appcat/.env || true
	echo "export IN_CLUSTER_SERVICE_CLUSTER_KUBECONFIG=../kindev/.kind/from-control-to-service-kubeconfig" >> component-appcat/.env; \
	echo "export SERVICE_CLUSTER_KUBECONFIG_CONTENT='$$(cat kindev/.kind/kind-config | base64 -w 0)'" >> component-appcat/.env; \
	echo "export IN_CLUSTER_CONTROL_PLANE_KUBECONFIG=../kindev/.kind/from-service-to-control-kubeconfig" >> component-appcat/.env; \
	echo "export CONTROL_PLANE_KUBECONFIG_CONTENT='$$(cat kindev/.kind/vcluster-config | base64 -w 0)'" >> component-appcat/.env;

.PHONY: e2e-tests
e2e-tests:
	cd component-appcat && \
	$(MAKE) e2e-test

.PHONY: run-single-e2e
run-single-e2e:
	cd component-appcat && \
	$(MAKE) run-single-e2e -e test=$(test)

DOCKER_CREDS_FILE := .inventage-credentials
FORGEJO_URL := http://forgejo.127.0.0.1.nip.io:8088
FORGEJO_REPO := gitea_admin/control-plane
FORGEJO_USERNAME := gitea_admin
FORGEJO_PASSWORD := adminadmin
FILE_PATH := 21_composition_vshn_keycloak.yaml
BRANCH := master

.PHONY: patch-keycloak-composition # Inject inventage docker credentials in the keycloak composition of forgejo repository
patch-keycloak-composition: check-docker-creds
	@echo "Patching Keycloak composition in Forgejo..."
	@set -a && . ./$(DOCKER_CREDS_FILE) && set +a && \
	if [ -z "$$inventage_registry_username" ] || [ -z "$$inventage_registry_password" ]; then \
		echo "ERROR: inventage_registry_username and inventage_registry_password must be set in $(DOCKER_CREDS_FILE)"; \
		exit 1; \
	fi && \
	echo "Fetching current file content..." && \
	CURRENT_CONTENT=$$(curl -s \
		-u "$(FORGEJO_USERNAME):$(FORGEJO_PASSWORD)" \
		"$(FORGEJO_URL)/api/v1/repos/$(FORGEJO_REPO)/contents/$(FILE_PATH)?ref=$(BRANCH)" | \
		jq -r '.content' | base64 -d) && \
	if [ -z "$$CURRENT_CONTENT" ]; then \
		echo "ERROR: Failed to fetch file from Forgejo"; \
		exit 1; \
	fi && \
	echo "Updating inventage docker registry credentials..." && \
	NEW_CONTENT=$$(echo "$$CURRENT_CONTENT" | \
		sed "s|registry_password:.*|registry_password: $$inventage_registry_password|" | \
		sed "s|registry_username:.*|registry_username: $$inventage_registry_username|") && \
	CONTENT_BASE64=$$(echo "$$NEW_CONTENT" | base64 -w 0) && \
	SHA=$$(curl -s \
		-u "$(FORGEJO_USERNAME):$(FORGEJO_PASSWORD)" \
		"$(FORGEJO_URL)/api/v1/repos/$(FORGEJO_REPO)/contents/$(FILE_PATH)?ref=$(BRANCH)" | \
		jq -r '.sha') && \
	echo "Committing changes to Forgejo (SHA: $$SHA)..." && \
	RESPONSE=$$(curl -s -w "\n%{http_code}" -X PUT \
		-u "$(FORGEJO_USERNAME):$(FORGEJO_PASSWORD)" \
		-H "Content-Type: application/json" \
		"$(FORGEJO_URL)/api/v1/repos/$(FORGEJO_REPO)/contents/$(FILE_PATH)" \
		-d "{\"content\":\"$$CONTENT_BASE64\",\"sha\":\"$$SHA\",\"branch\":\"$(BRANCH)\",\"message\":\"Update registry credentials\"}") && \
	HTTP_CODE=$$(echo "$$RESPONSE" | tail -n1) && \
	BODY=$$(echo "$$RESPONSE" | head -n-1) && \
	if [ "$$HTTP_CODE" = "200" ] || [ "$$HTTP_CODE" = "201" ]; then \
		echo "✓ Keycloak composition updated successfully"; \
		echo "View changes: $(FORGEJO_URL)/$(FORGEJO_REPO)/src/branch/$(BRANCH)/$(FILE_PATH)"; \
	else \
		echo "ERROR: Failed to update file (HTTP $$HTTP_CODE)"; \
		echo "$$BODY" | jq .; \
		exit 1; \
	fi

.PHONY: check-docker-creds
check-docker-creds:
	@if [ ! -f "$(DOCKER_CREDS_FILE)" ]; then \
		echo "ERROR: Docker credentials file '$(DOCKER_CREDS_FILE)' not found!"; \
		echo ""; \
		echo "Create it with:"; \
		echo "  cat > .docker-credentials << EOF"; \
		echo "  inventage_registry_username=your-username"; \
		echo "  inventage_registry_password=your-password"; \
		echo "  EOF"; \
		echo ""; \
		exit 1; \
	fi
