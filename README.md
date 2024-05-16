
<table style="width:100%">
  <tr>
    <td colspan=2><strong>
    k3d-faas
      </strong>&nbsp;&nbsp;&nbsp;&nbsp;
    </td>
  </tr>
  <tr>
    <td width=15%><img src=img/icon.png style="width:150px"></td>
    <td>
      Laboratory for working with Functions as a Service on kubernetes
      <br/><br/>
      <a href="https://github.com/elo-enterprises/k3d-faas/actions/workflows/docker-test.yml"><img src="https://github.com/elo-enterprises/k3d-faas/actions/workflows/docker-test.yml/badge.svg"></a>
    </td>
  </tr>
</table>

-------------------------------------------------------------

<div class="toc">
<ul>
<li><a href="#overview">Overview</a></li>
<li><a href="#features">Features</a></li>
<li><a href="#quick-start">Quick Start</a><ul>
<li><a href="#clonebuildtest-this-repo">Clone/Build/Test This Repo</a></li>
</ul>
</li>
<li><a href="#references">References</a></li>
<li><a href="#known-limitations-and-issues">Known Limitations and Issues</a></li>
</ul>
</div>


-------------------------------------------------------------

## Overview

A self-contained, batteries-included environment / workbench for prototyping Functions-as-a-Service stuff on Kubernetes.  

* Uses [k3d](http://k3d.io) for project-local clusters (no existing cluster required)
* Uses [k8s-tools](https://github.com/elo-enterprises/k8s-tools) for [project automation](Makefile)
* Multiple backends for easy experimentation
    * [Fission](https://fission.io/docs)
    * [Knative-Events](https://knative.dev/docs)
    * [Argo-Events](#)

**Besides a localhost-friendly cluster, there are no build dependencies at all except for docker.**  All of k3d/helm/kubectl & knative/argo/fission CLIs use independently versioned containers, starting with the alpine-k8s base.  The entire stack in this repository is exercised by tests with github actions, and should work anywhere else that is configured for docker-in-docker support.

**This is intended to be a solid reference architecture for cluster-bootstrapping**, but it's mainly for experiments/benchmarking and isn't exactly what you would call production-ready.  But it's a good start for further iteration, because it's easy to yank out the components you don't need and customize the ones you want to keep.  

* **To point this automation at an existing cluster,** just disable the k3d bootstrap and use a different KUBECONFIG.
* **Keeping the from-scratch cluster build but switching the backend from k3d to something like EKS** should also be fairly straightforward.  
* **Event-sourcing from something like SQS takes more signficant effort,** but hopefully the automation layout makes it clear how to get started.

-------------------------------------------------------------

## Features

* Bundles Fission, Knative, Argo & OpenWhisk CLI tools.  
    * You can use those CLIs with the local deployments infrastructure, or against existing deployments.
* E2E demo for basic Fission infrastructure & application deployment
* E2E demo for basic Knative infrastructure deployment *(app coming soon)*

* E2E demo for basic Argo infrastructure deployment *(app coming soon)*

-------------------------------------------------------------

## Quick Start

### Clone/Build/Test This Repo

```bash
# for ssh
$ git clone git@github.com:elo-enterprises/k3d-faas.git

# or for http
$ git clone https://github.com/elo-enterprises/k3d-faas

# teardown, setup, and exercise the entire stack
$ make clean bootstrap deploy test

# teardown/setup just the cluster
$ make clean bootstrap
INFO[0000] No clusters found                            
Docker version 26.1.2, build 211e74b
k3d version v5.6.3
k3s version v1.28.8-k3s1 (default)
INFO[0000] Using config file faas.cluster.k3d.yaml (k3d.io/v1alpha5#simple) 
INFO[0000] portmapping '8080:80' targets the loadbalancer: defaulting to [servers:*:proxy agents:*:proxy] 
INFO[0000] Prep: Network                                
INFO[0000] Created network 'k3d-faas'                   
INFO[0000] Created image volume k3d-faas-images         
INFO[0000] Creating node 'docker-io'                    
INFO[0000] Successfully created registry 'docker-io'    
INFO[0000] Starting new tools node...                   
INFO[0000] Creating initializing server node            
INFO[0000] Creating node 'k3d-faas-server-0'            
INFO[0000] Starting node 'k3d-faas-tools'               
INFO[0001] Creating node 'k3d-faas-server-1'            
INFO[0002] Creating node 'k3d-faas-server-2'            
INFO[0002] Creating node 'k3d-faas-agent-0'             
INFO[0002] Creating node 'k3d-faas-agent-1'             
INFO[0002] Creating node 'k3d-faas-agent-2'             
INFO[0002] Creating node 'k3d-faas-agent-3'             
INFO[0002] Creating node 'k3d-faas-agent-4'             
INFO[0002] Creating node 'k3d-faas-agent-5'             
INFO[0002] Creating node 'k3d-faas-agent-6'             
INFO[0002] Creating LoadBalancer 'k3d-faas-serverlb'    
INFO[0002] Using the k3d-tools node to gather environment information 
INFO[0002] HostIP: using network gateway 192.168.192.1 address 
INFO[0002] Starting cluster 'faas'                      
INFO[0002] Starting the initializing server...          
INFO[0002] Starting node 'k3d-faas-server-0'            
INFO[0005] Starting servers...                          
INFO[0005] Starting node 'k3d-faas-server-1'            
INFO[0026] Starting node 'k3d-faas-server-2'            
INFO[0042] Starting agents...                           
INFO[0043] Starting node 'k3d-faas-agent-3'             
INFO[0043] Starting node 'k3d-faas-agent-4'             
INFO[0043] Starting node 'k3d-faas-agent-5'             
INFO[0043] Starting node 'k3d-faas-agent-1'             
INFO[0043] Starting node 'k3d-faas-agent-0'             
INFO[0043] Starting node 'k3d-faas-agent-6'             
INFO[0043] Starting node 'k3d-faas-agent-2'             
INFO[0049] Starting helpers...                          
INFO[0049] Starting node 'docker-io'                    
INFO[0049] Starting node 'k3d-faas-serverlb'            
INFO[0055] Injecting records for hostAliases (incl. host.k3d.internal) and for 12 network members into CoreDNS configmap... 
INFO[0058] Cluster 'faas' created successfully!         
INFO[0058] You can now use it like this:                
kubectl cluster-info
./faas.profile.yaml
CLUSTER_NAME=faas
CLUSTER_CONFIG=faas.cluster.k3d.yaml
KUBECONFIG=./faas.profile.yaml
Kubernetes control plane is running at https://0.0.0.0:6551
CoreDNS is running at https://0.0.0.0:6551/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
Metrics-server is running at https://0.0.0.0:6551/api/v1/namespaces/kube-system/services/https:metrics-server:https/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
NAME                STATUS   ROLES                       AGE   VERSION
k3d-faas-agent-0    Ready    <none>                      32s   v1.28.8+k3s1
k3d-faas-agent-1    Ready    <none>                      33s   v1.28.8+k3s1
k3d-faas-agent-2    Ready    <none>                      32s   v1.28.8+k3s1
k3d-faas-agent-3    Ready    <none>                      33s   v1.28.8+k3s1
k3d-faas-agent-4    Ready    <none>                      33s   v1.28.8+k3s1
k3d-faas-agent-5    Ready    <none>                      32s   v1.28.8+k3s1
k3d-faas-agent-6    Ready    <none>                      31s   v1.28.8+k3s1
k3d-faas-server-0   Ready    control-plane,etcd,master   71s   v1.28.8+k3s1
k3d-faas-server-1   Ready    control-plane,etcd,master   54s   v1.28.8+k3s1
k3d-faas-server-2   Ready    control-plane,etcd,master   37s   v1.28.8+k3s1
NAME              STATUS   AGE
default           Active   73s
kube-node-lease   Active   73s
kube-public       Active   73s
kube-system       Active   73s


# piecewise setup / teardown for infrastructure and apps
$ make knative
$ make argo
$ make fission

# equivalently, with more granularity:
$ make knative_infra.teardown knative_infra.setup knative_app.setup
$ make argo.teardown argo.setup argo_app.setup
$ make fission_infra.teardown fission_infra.setup fission_app.setup

# test infrastructure components piecewise
make fission_infra.test
make knative_infra.test
make argo_infra.test

# test application components piecewise
make fission_app.test
make knative_app.test
make argo_app.test
```

-------------------------------------------------------------

# References

1. https://argoproj.github.io/argo-events/installation/
1. <https://danquack.dev/blog/creating-faas-in-k8s-with-argo-events>

-------------------------------------------------------------

# Known Limitations and Issues

1. Placeholder
1. Placeholder
1. Placeholder

