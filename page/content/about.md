---
title: "About This Workshop"
description: "Background, technology stack, and how this site itself is deployed."
date: 2024-01-01
---

## Meta: This Site Is The Workshop

The Hugo page you are reading right now **is** the workshop application. It was built, pushed to Quay.io, and deployed to this OpenShift namespace by the exact same Tekton pipeline and ArgoCD setup described in the modules.

Every time someone commits to the workshop repository and the content changes, the pipeline rebuilds this site, creates a new container image, and ArgoCD rolls it out — automatically.

---

## Technology Stack

### 🔴 Red Hat OpenShift
The platform everything runs on. OpenShift is an enterprise Kubernetes distribution with built-in developer tooling, a web console, operator framework, and native CI/CD integrations via operators.

### ⚡ Tekton (OpenShift Pipelines)
Tekton is the CNCF standard for cloud-native CI. Pipelines, Tasks, and PipelineRuns are all Kubernetes Custom Resources — they live in your cluster alongside your application and are managed the same way.

### ⚡ Tekton Pipelines
Tekton is a cloud-native CI framework built on Kubernetes CRDs. PipelineRuns are triggered manually with `oc create -f` from templates in `tekton/pipelineruns/`. Pipelines as Code (automatic webhook triggering) will be added in a future workshop iteration.

### 🔄 ArgoCD (OpenShift GitOps)
ArgoCD implements the GitOps pattern for CD. Git is the single source of truth. ArgoCD continuously reconciles the cluster state against Git.

### ⎈ Helm
Helm templates the Kubernetes manifests. A single chart handles all three environments via separate values files.

### 📦 Quay.io
Red Hat's container registry with robot accounts, vulnerability scanning, and OpenShift integration.

### 🏗️ Hugo
One of the fastest static site generators. Written in Go, compiles in milliseconds.

### 🌐 Hummingbird httpd
`quay.io/hummingbird/httpd` — lightweight, OpenShift-compatible HTTP server running on port 8080 without root.

---

## Contributing

Found a mistake? Fix it:

1. Edit the Markdown under `page/content/posts/`
2. Commit and push to `main`
3. Watch the pipeline rebuild and redeploy
4. See your fix live in dev within minutes

That's the whole point. 🚀
