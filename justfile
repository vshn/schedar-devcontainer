# Default recipe to display help
default:
    @just --list

# Initialize all git submodules
clone-all:
    git -C appcat pull || git clone git@github.com:vshn/appcat || true
    git -C component-appcat pull || git clone git@github.com:vshn/component-appcat || true
    git -C component-spks-crossplane pull || git clone git@git.vshn.net:swisscompks/component-spks-crossplane.git || true
    git -C component-exporter-filterproxy pull || git clone git@github.com:vshn/component-exporter-filterproxy.git || true
    git -C kindev pull || git clone git@github.com:vshn/kindev || true
    git -C appcat-charts pull || git clone git@github.com:vshn/appcat-charts || true

# Delete all submodules
clean-container:
    rm -rf appcat component-appcat component-spks-crossplane kindev

# Setup spks kindev environment
setup-spks:
    cd kindev && just spks
    cp kindev/.kind/kind-config ~/.kube/config

# Setup kindev environment
setup-kindev:
    cd kindev && just vshnall
    cp kindev/.kind/kind-config ~/.kube/config

# Clean kindev
clean-kindev:
    cd kindev && just clean

# Push AppCat configuration converged mode to local forgejo. By default it will try to connect to AppCat running in debug mode. Use `DEBUG=false just push-golden` to run against containers in the cluster
push-golden DEBUG="true":
    #!/usr/bin/env bash
    set -euxo pipefail
    HOST=$(docker inspect kindev-control-plane | jq '.[0].NetworkSettings.Networks.kind.Gateway')
    yq '.parameters.appcat.proxyFunction |= {{DEBUG}}' component-appcat/tests/dev.yml | diff -B component-appcat/tests/dev.yml - | patch component-appcat/tests/dev.yml -
    yq '.parameters.appcat.grpcEndpoint |= '"$HOST"'+":9443"' component-appcat/tests/dev.yml | diff -B component-appcat/tests/dev.yml - | patch component-appcat/tests/dev.yml -
    cd component-appcat && just push-golden
    cd ..
    just export-cluster-env-single
    just patch-keycloak-composition gitea_admin/appcat

# Push AppCat configuration non-converged mode to local forgejo. By default it will try to connect to AppCat running in debug mode. Use `DEBUG=false just push-non-converged` to run against containers in the cluster
push-non-converged DEBUG="true":
    #!/usr/bin/env bash
    set -euo pipefail
    HOST=$(docker inspect kindev-control-plane | jq '.[0].NetworkSettings.Networks.kind.Gateway')
    yq '.parameters.appcat.proxyFunction |= {{DEBUG}}' component-appcat/tests/control-plane.yml | diff -B component-appcat/tests/control-plane.yml - | patch component-appcat/tests/control-plane.yml -
    yq '.parameters.appcat.grpcEndpoint |= '"$HOST"'+":9443"' component-appcat/tests/control-plane.yml | diff -B component-appcat/tests/control-plane.yml - | patch component-appcat/tests/control-plane.yml -
    cd component-appcat && just push-non-converged
    cd ../kindev
    export serviceCluster=$(just vcluster-host-kubeconfig)
    export controlCluster=$(just vcluster-in-cluster-kubeconfig)
    cd ..
    yq '.parameters.appcat.clusterManagementSystem.serviceClusterKubeconfigs[0].config |= strenv(serviceCluster)' component-appcat/tests/control-plane.yml | diff -B component-appcat/tests/control-plane.yml - | patch component-appcat/tests/control-plane.yml -
    yq '.parameters.appcat.clusterManagementSystem.controlPlaneKubeconfig |= strenv(controlCluster)' component-appcat/tests/service-cluster.yml | diff -B component-appcat/tests/service-cluster.yml - | patch component-appcat/tests/service-cluster.yml -
    cd component-appcat && just push-non-converged
    cd ..
    just export-cluster-env-multi
    cp kindev/.kind/vcluster-config ~/.kube/config
    just patch-keycloak-composition gitea_admin/control-plane

# Push SPKS configuration
push-spks DEBUG="true":
    #!/usr/bin/env bash
    set -euo pipefail
    yq '.parameters.spks_crossplane.proxyFunction |= {{DEBUG}}' component-spks-crossplane/tests/control-plane.yml | diff -B component-spks-crossplane/tests/control-plane.yml - | patch component-spks-crossplane/tests/control-plane.yml -
    cd component-spks-crossplane && just push-non-converged
    cd ../kindev
    export appcat_namespace=spks-crossplane
    export serviceCluster=$(just vcluster-host-kubeconfig)
    export controlCluster=$(just vcluster-in-cluster-kubeconfig)
    cd ..
    yq '.parameters.spks_crossplane.clusterManagementSystem.serviceClusterKubeconfigs[0].config |= strenv(serviceCluster)' component-spks-crossplane/tests/control-plane.yml | diff -B component-spks-crossplane/tests/control-plane.yml - | patch component-spks-crossplane/tests/control-plane.yml -
    yq '.parameters.spks_crossplane.clusterManagementSystem.controlPlaneKubeconfig |= strenv(controlCluster)' component-spks-crossplane/tests/service-cluster.yml | diff -B component-spks-crossplane/tests/service-cluster.yml - | patch component-spks-crossplane/tests/service-cluster.yml -
    cd component-spks-crossplane && just push-non-converged
    cd ../component-exporter-filterproxy && just push-non-converged
    cd ../appcat-charts && just push-local

# Export environment variables for e2e tests in single cluster mode (converged)
export-cluster-env-single:
    #!/usr/bin/env bash
    set -euo pipefail
    rm -f component-appcat/.env || true
    cp kindev/.kind/kind-config kindev/.kind/in-cluster-kind-config
    yq -i '.clusters[0].cluster.server = "https://kubernetes.default.svc:443"' kindev/.kind/in-cluster-kind-config
    echo "export IN_CLUSTER_CONTROL_PLANE_KUBECONFIG=../kindev/.kind/in-cluster-kind-config" >> component-appcat/.env
    echo "export IN_CLUSTER_SERVICE_CLUSTER_KUBECONFIG=../kindev/.kind/in-cluster-kind-config" >> component-appcat/.env
    echo "export CONTROL_PLANE_KUBECONFIG_CONTENT='$(cat kindev/.kind/kind-config | base64 -w 0)'" >> component-appcat/.env
    echo "export SERVICE_CLUSTER_KUBECONFIG_CONTENT='$(cat kindev/.kind/kind-config | base64 -w 0)'" >> component-appcat/.env

# Export environment variables for e2e tests in multi cluster mode (non-converged)
export-cluster-env-multi:
    #!/usr/bin/env bash
    set -euo pipefail
    cd kindev && just vcluster-host-kubeconfig > .kind/from-control-to-service-kubeconfig
    cd kindev && just vcluster-in-cluster-kubeconfig > .kind/from-service-to-control-kubeconfig
    rm -f component-appcat/.env || true
    echo "export IN_CLUSTER_SERVICE_CLUSTER_KUBECONFIG=../kindev/.kind/from-control-to-service-kubeconfig" >> component-appcat/.env
    echo "export SERVICE_CLUSTER_KUBECONFIG_CONTENT='$(cat kindev/.kind/kind-config | base64 -w 0)'" >> component-appcat/.env
    echo "export IN_CLUSTER_CONTROL_PLANE_KUBECONFIG=../kindev/.kind/from-service-to-control-kubeconfig" >> component-appcat/.env
    echo "export CONTROL_PLANE_KUBECONFIG_CONTENT='$(cat kindev/.kind/vcluster-config | base64 -w 0)'" >> component-appcat/.env

# Run e2e tests
e2e-tests:
    cd component-appcat && just e2e-test

# Run single e2e test (use: just run-single-e2e test=TestName)
run-single-e2e test="":
    cd component-appcat && just run-single-e2e {{test}}

# Inject inventage docker credentials in the keycloak composition of forgejo repository
patch-keycloak-composition FORGEJO_REPO="gitea_admin/control-plane":
    #!/usr/bin/env bash
    set -euo pipefail
    DOCKER_CREDS_FILE=".inventage-credentials"
    FORGEJO_URL="http://forgejo.127.0.0.1.nip.io:8088"
    FORGEJO_USERNAME="gitea_admin"
    FORGEJO_PASSWORD="adminadmin"
    FILE_PATH="21_composition_vshn_keycloak.yaml"
    BRANCH="master"

    if [ ! -f "$DOCKER_CREDS_FILE" ]; then
        echo "ERROR: Docker credentials file '$DOCKER_CREDS_FILE' not found!"
        echo ""
        echo "Create it with:"
        echo "  cat > $DOCKER_CREDS_FILE << EOF"
        echo "  inventage_registry_username=your-username"
        echo "  inventage_registry_password=your-password"
        echo "  EOF"
        echo ""
        exit 1
    fi

    echo "Patching Keycloak composition in Forgejo..."
    set -a && . ./$DOCKER_CREDS_FILE && set +a

    if [ -z "$inventage_registry_username" ] || [ -z "$inventage_registry_password" ]; then
        echo "ERROR: inventage_registry_username and inventage_registry_password must be set in $DOCKER_CREDS_FILE"
        exit 1
    fi

    echo "Fetching current file content..."
    CURRENT_CONTENT=$(curl -s \
        -u "$FORGEJO_USERNAME:$FORGEJO_PASSWORD" \
        "$FORGEJO_URL/api/v1/repos/{{FORGEJO_REPO}}/contents/$FILE_PATH?ref=$BRANCH" | \
        jq -r '.content' | base64 -d)

    if [ -z "$CURRENT_CONTENT" ]; then
        echo "ERROR: Failed to fetch file from Forgejo"
        exit 1
    fi

    echo "Updating inventage docker registry credentials..."
    NEW_CONTENT=$(echo "$CURRENT_CONTENT" | \
        sed "s|registry_password:.*|registry_password: $inventage_registry_password|" | \
        sed "s|registry_username:.*|registry_username: $inventage_registry_username|")

    CONTENT_BASE64=$(echo "$NEW_CONTENT" | base64 -w 0)
    SHA=$(curl -s \
        -u "$FORGEJO_USERNAME:$FORGEJO_PASSWORD" \
        "$FORGEJO_URL/api/v1/repos/{{FORGEJO_REPO}}/contents/$FILE_PATH?ref=$BRANCH" | \
        jq -r '.sha')

    echo "Committing changes to Forgejo (SHA: $SHA)..."
    RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
        -u "$FORGEJO_USERNAME:$FORGEJO_PASSWORD" \
        -H "Content-Type: application/json" \
        "$FORGEJO_URL/api/v1/repos/{{FORGEJO_REPO}}/contents/$FILE_PATH" \
        -d "{\"content\":\"$CONTENT_BASE64\",\"sha\":\"$SHA\",\"branch\":\"$BRANCH\",\"message\":\"Update registry credentials\"}")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | head -n-1)

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        echo "✓ Keycloak composition updated successfully"
        echo "View changes: $FORGEJO_URL/{{FORGEJO_REPO}}/src/branch/$BRANCH/$FILE_PATH"
    else
        echo "ERROR: Failed to update file (HTTP $HTTP_CODE)"
        echo "$BODY" | jq .
        exit 1
    fi
