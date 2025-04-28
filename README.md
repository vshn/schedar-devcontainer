# Schedar-devcontainer

This repo combines our various repositories into one, for a better dev UX.

Just clone this repo, open it with a devcontainer compatible IDE and start the devcontainer.

After the container has started, chose a deployment method:

* converged: everything on the same cluster -> `make push-golden`
* non-converged: control cluster and service cluster split -> `make push-non-converged`

After these you have to visit http://argocd.127.0.0.1.nip.io:8088 and re-trigger the sync, otherwise it will never sync.

By default the setup deploys with the debug proxy enabled. So to actually deploy a service, please start the appcat.

For more information about developing the various projects, please check out their respective readme files.

## Getting started with devcontainers

This project contains a `.devcontainer` folder, which enables devcontainer support in vscode and other IDEs.
Make sure you've installed the dev containers extension for vscode.

Then open the command palette and do `Dev Containers: Reopen in container`.
The first time doing this will take quite some as it builds the whole container.
After building the container it will spin up kindev, which will also take some time.

Once it's finished there should be a ready to go dev environment to use.

The container will contain:
* go
* helm
* kubectl
* yq
* kubecolor

Additionally, it will install some useful extensions for vscode to make development easier.

Kindev will be installed in the `.kind` folder.
Vscode handles all port-forwarding automagically, so kindev and all endpoints will be available all the same from the host.
Simply point `KUBECONFIG` to `.kind/.kind/kind-config` and use `kubectl` as usual.

> [!NOTE]
> On linux, Podman and rootless Docker have been found to cause issues.
> Ensure that you are using **rootful Docker** to save yourself loads of trouble.
>
> Additionally, on Fedora, you might encounter issues with `iptables`.
> Execute the following on the host prior to building the devcontainer:
> ```bash
> sudo dnf install -y iptables-legacy
> sudo modprobe ip_tables
> echo 'ip_tables' | sudo tee /etc/modules
> ```
>
> *To further debug dind, consult `/tmp/dockerd.log` in the container.*
> Please refer to official documentation under: https://docs.docker.com/engine/install/

### Devcontainer customizations

It's possible to customize the devcontainer.
By setting `"terminal.integrated.defaultProfile.linux": "zsh"` in the vscode config, it's possible to switch the default shell to zsh.

It's also possible to provide your own dotfiles. They will be installed after the kindev setup has finished.
For that, simply write a small script that contains all your desired configurations and put it in a publicly available repository.
Here's an example repo: https://github.com/lugoues/vscode-dev-containers-dotfiles

After that set this configuration in vscode:
```
{
  "dotfiles.repository": "your-github-id/your-dotfiles-repo",
  "dotfiles.targetPath": "~/dotfiles",
  "dotfiles.installCommand": "install.sh"
}
```
