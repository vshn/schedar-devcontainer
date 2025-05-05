SHELL:=/bin/bash

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

clone-all: ## Initialize all git submodules
	git submodule init
	git submodule update

clean-container: ## Delete all submodules
	rm -rf appcat component-appcat kindev

setup-kindev: ## Setup kindev environment
	cd kindev && \
	make vshnall
	cp kindev/.kind/kind-config ~/.kube/config

clean-kindev: ## Clean kindev
	cd kindev && \
	make clean

push-golden: DEBUG=true
push-golden: ## Push AppCat configuration converged mode to local forgejo. By default it will try to connect to AppCat running in debug mode. Use `-e DEBUG=false` to run against containers in the cluster
	yq '.parameters.appcat.proxyFunction |= $(DEBUG)' component-appcat/tests/dev.yml | diff -B component-appcat/tests/dev.yml - | patch component-appcat/tests/dev.yml -
	cd component-appcat && \
	make push-golden

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
	make push-non-converged



