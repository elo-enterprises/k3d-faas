
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

**This is intended to be a solid reference architecture for cluster-bootstrapping**, but as for the FaaS platforms, it's mainly for experiments and benchmarking and not what you would call production-ready.  

It's a good start for further iteration though, because it's easy to yank out the components you don't need and customize the ones you want to keep.  If you're interested in that, next steps might involve:

* **Pointing this automation at an existing cluster** involves disabling [the k3d bootstrap](#) and setting a different KUBECONFIG.
* **Keeping the from-scratch cluster build but switching the backend from k3d to something like EKS** should also be fairly straightforward.  
* **Event-sourcing from something like SQS takes more signficant effort,** but hopefully the automation layout makes it clear how to get started.

-------------------------------------------------------------

## Features

* Bundles [Fission](#), [Knative](#), ~~OpenWhisk~~, & [Argo](#)CLI tools.  
    * You can use those CLIs with the local deployments infrastructure, or against existing deployments.
* E2E demo for basic Fission infrastructure & application deployment
* E2E demo for basic Knative infrastructure deployment *(app coming soon)*
* E2E demo for basic Argo infrastructure/app deployment
-------------------------------------------------------------

## Quick Start

### Clone/Build/Test This Repo

```bash
# for ssh
$ git clone git@github.com:elo-enterprises/k3d-faas.git

# or for http
$ git clone https://github.com/elo-enterprises/k3d-faas

# teardown & setup just for the k3d cluster
$ make clean bootstrap

# teardown, setup, and exercise the entire stack
$ make clean bootstrap deploy test

# piecewise setup for platforms (infra+apps)
 $ make argo.setup
 $ make fission.setup
 $ make prometheus.setup

# tests by platform (infra+apps)
 $ make argo.test
 $ make cluster.test
 $ make fission.test
 $ make prometheus.test

```

Plus more granular targets 

```bash 
# piecewise setup for platform-infrastructure
 $ make argo.infra.setup
 $ make fission.infra.setup
 $ make knative.infra.setup
 $ make self.fission.infra.setup
 $ make self.knative.infra.setup

# piecewise setup for platform-apps
 $ make argo.app.setup
 $ make fission.app.setup
 $ make knative.app.setup
 $ make self.argo.app.setup
 $ make self.knative.app.setup

```
-------------------------------------------------------------

# References

1. https://argoproj.github.io/argo-events/installation/
1. <https://danquack.dev/blog/creating-faas-in-k8s-with-argo-events>

