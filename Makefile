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


push-spks: DEBUG=true
push-spks:
	yq '.parameters.spks_crossplane.proxyFunction |= $(DEBUG)' component-spks-crossplane/tests/control-plane.yml | diff -B component-spks-crossplane/tests/control-plane.yml - | patch component-spks-crossplane/tests/control-plane.yml -
	cd component-spks-crossplane && \
	make push-non-converged && \
	cd ../kindev && \
	export serviceCluster=$$(make vcluster-host-kubeconfig | grep -v "Leaving" | grep -v "Entering") && \
	export controlCluster=$$(make vcluster-in-cluster-kubeconfig | grep -v 'make' | grep -v "Entering") && \
	cd .. && \
	yq '.parameters.spks_crossplane.clusterManagementSystem.serviceClusterKubeconfigs[0].config |= strenv(serviceCluster)' component-spks-crossplane/tests/control-plane.yml | diff -B component-spks-crossplane/tests/control-plane.yml - | patch component-spks-crossplane/tests/control-plane.yml - && \
	yq '.parameters.spks_crossplane.clusterManagementSystem.controlPlaneKubeconfig |= strenv(controlCluster)' component-spks-crossplane/tests/service-cluster.yml | diff -B component-spks-crossplane/tests/service-cluster.yml - | patch component-spks-crossplane/tests/service-cluster.yml - && \
	cd component-spks-crossplane && \
	make push-non-converged && \
	cd ../component-exporter-filterproxy && \
	make push-non-converged
