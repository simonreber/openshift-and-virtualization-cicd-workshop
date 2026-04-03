---
title: "07 · Troubleshooting & Tips"
description: "Common issues, debug commands, and tips for getting the most out of this workshop setup."
date: 2024-01-07
weight: 7
tags: ["troubleshooting", "debug", "tips"]
---

## Debug Cheatsheet

Quick-reference commands for diagnosing problems anywhere in the stack.

---

## Tekton / Pipeline Issues

### Pipeline not triggering after a push

```bash
# 1. Check PaC controller is running
oc get pods -n pipelines-as-code

# 2. Check PaC logs for webhook receipt
oc logs -n pipelines-as-code \
  deployment/pipelines-as-code-controller -f

# 3. Verify Repository resource is healthy
oc get repository workshop-app -n workshop-ci -o yaml

# 4. Check GitHub webhook delivery
# GitHub → repo → Settings → Webhooks → Recent Deliveries
```

Common causes:
- Webhook secret mismatch (check `github-webhook-secret` vs GitHub setting)
- PAC controller route is HTTP but GitHub sends HTTPS — or vice versa
- Branch name in annotation doesn't match (case-sensitive)

### PipelineRun stuck in Pending

```bash
oc describe pipelinerun <name> -n workshop-ci
oc get pods -n workshop-ci | grep <pipelinerun-name>
```

Common causes:
- PVC is not Bound → `oc get pvc -n workshop-ci`
- Insufficient cluster resources → `oc describe node`
- Image pull error on a task step → `oc describe pod <pod>`

### Buildah fails with permission errors

The buildah task requires a privileged SCC. Verify:

```bash
oc get scc privileged -o jsonpath='{.users}' | tr ',' '\n' | grep pipeline
```

If not present:

```bash
oc adm policy add-scc-to-user privileged \
  system:serviceaccount:workshop-ci:pipeline
```

### git push in update-helm-values fails

```bash
# Check github-token secret exists and has the correct key
oc get secret github-token -n workshop-ci -o jsonpath='{.data}' \
  | python3 -c "import sys,json,base64; \
    d=json.load(sys.stdin); \
    [print(k,'=',base64.b64decode(v).decode()[:8]+'...') for k,v in d.items()]"
```

Make sure the PAT has `repo` (write) scope and hasn't expired.

---

## ArgoCD Issues

### Application stuck in OutOfSync

```bash
oc get application workshop-app-dev -n openshift-gitops -o yaml \
  | grep -A 20 "status:"
```

```bash
# Force refresh (re-read Git)
oc annotate application workshop-app-dev \
  -n openshift-gitops \
  argocd.argoproj.io/refresh=hard
```

### Application stuck in Progressing / Degraded

```bash
# Check the actual pods
oc get pods -n workshop-dev
oc describe pod -n workshop-dev -l app.kubernetes.io/name=workshop-app

# Check events
oc get events -n workshop-dev --sort-by=.lastTimestamp | tail -20
```

### ArgoCD can't access the Git repository

```bash
# Check ArgoCD repo connection
oc exec -n openshift-gitops \
  deployment/openshift-gitops-server \
  -- argocd repo list
```

If it shows an error, re-add the credentials:

```bash
oc exec -n openshift-gitops \
  deployment/openshift-gitops-server \
  -- argocd repo add \
     "https://github.com/${GITHUB_ORG}/${GITHUB_REPO}" \
     --username "${GITHUB_ORG}" \
     --password "ghp_YOUR_TOKEN"
```

### Helm rendering errors

Test Helm rendering locally:

```bash
helm template workshop-app helm/workshop-app \
  -f helm/workshop-app/values.yaml \
  -f helm/workshop-app/values-dev.yaml
```

---

## Application / Image Issues

### Image pull error in dev/test/prod

```bash
oc get events -n workshop-dev \
  --field-selector reason=Failed \
  --sort-by=.lastTimestamp

# Verify the secret is linked to the default SA
oc describe sa default -n workshop-dev | grep quay
```

Re-link the secret if missing:

```bash
oc secrets link default quay-credentials --for=pull -n workshop-dev
```

### Route not accessible

```bash
# Check the route exists
oc get route workshop-app -n workshop-dev

# Check the service endpoints
oc get endpoints workshop-app -n workshop-dev

# Check pod is Running and Ready
oc get pods -n workshop-dev -l app.kubernetes.io/name=workshop-app
```

### Hugo build produces an empty site

```bash
# Check hugo output inside the pipeline logs
tkn taskrun logs -n workshop-ci \
  -l tekton.dev/task=build-hugo --last -f
```

Verify `page/config.toml` has a valid `baseURL` (it should be `"/"` for this setup).

---

## General OpenShift Tips

### Get all events sorted by time

```bash
oc get events -n workshop-ci \
  --sort-by='.lastTimestamp' | tail -30
```

### Tail logs from all pods with a label

```bash
oc logs -n workshop-dev -l app.kubernetes.io/name=workshop-app -f
```

### Port-forward for local testing

```bash
oc port-forward -n workshop-dev \
  svc/workshop-app 8080:8080
# Then open http://localhost:8080
```

### Delete all failed PipelineRuns

```bash
oc delete pipelineruns -n workshop-ci \
  --field-selector=status.conditions[0].reason=Failed
```

---

## Useful Labels & Selectors

Tekton automatically applies labels you can filter on:

```bash
# All pods from a specific PipelineRun
oc get pods -n workshop-ci \
  -l tekton.dev/pipelineRun=<name>

# All TaskRuns from a Pipeline
oc get taskruns -n workshop-ci \
  -l tekton.dev/pipeline=workshop-build-pipeline

# Latest PipelineRun name
oc get pipelinerun -n workshop-ci \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1].metadata.name}'
```

---

## Summary

You now have a full toolkit for debugging every layer of the stack. Head back to any module if something didn't work, or explore the **[About page](/about/)** for more context.
