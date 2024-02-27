# microk8s

## installation

```bash
sudo snap install microk8s --classic
sudo usermod -a -G microk8s ubuntu
mkdir .kube
sudo chown -R ubuntu .kube
# restart shell
microk8s enable hostpath-storage dns:1.1.1.1 ingress cert-manager
```

```
enabled:
    cert-manager         # (core) Cloud native certificate management
    dns                  # (core) CoreDNS
    ha-cluster           # (core) Configure high availability on the current node
    helm                 # (core) Helm - the package manager for Kubernetes
    helm3                # (core) Helm 3 - the package manager for Kubernetes
    hostpath-storage     # (core) Storage class; allocates storage from host directory
    ingress              # (core) Ingress controller for external access
    storage              # (core) Alias to hostpath-storage add-on, deprecated
```
