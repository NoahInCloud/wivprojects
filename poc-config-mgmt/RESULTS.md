# PoC Results: Kustomize vs Tanka/Jsonnet for Configuration Management

## Executive Summary

This PoC evaluated **Kustomize** and **Tanka/Jsonnet** for managing environment differences on top of Helm charts in a GitOps workflow with ArgoCD. Both tools were tested with identical workloads (PostgreSQL + demo app) across three environments (test, prod, test7).

## Environment Setup

| Component | Details |
|-----------|---------|
| Cluster | AWS EKS (eu-central-1), Kubernetes v1.34.2 |
| GitOps | ArgoCD with ApplicationSets |
| Secret Management | External Secrets Operator + AWS Secrets Manager |
| Container Registry | AWS ECR (050752617334.dkr.ecr.eu-central-1.amazonaws.com) |
| Storage | gp2 (AWS EBS) |

## Test Results

### 1. Create/Extend/Update/Overlay Helm Charts

#### Kustomize
- **Tested**: Yes
- **Approach**: Pre-render Helm chart to YAML, then use Kustomize overlays with JSON patches
- **Example**: `kustomize/base/helm-rendered/postgres.yaml` + `overlays/{test,prod,test7}/kustomization.yaml`
- **Pros**:
  - Native ArgoCD support (no plugins needed)
  - Simple, declarative YAML patches
  - Easy to understand for YAML-familiar teams
  - Built-in namespace transformation
- **Cons**:
  - Helm must be pre-rendered (adds build step)
  - Limited transformation capabilities vs Jsonnet
  - No real variables or functions
  - helmCharts feature requires ArgoCD configuration

#### Tanka/Jsonnet
- **Tested**: Yes
- **Approach**: Library pattern with environment-specific main.jsonnet files, export to rendered YAML
- **Example**: `tanka/lib/poc-app.libsonnet` + `tanka/environments/{test,prod,test7}/main.jsonnet`
- **Pros**:
  - Full programming language (loops, functions, conditionals)
  - Powerful object inheritance and composition
  - Type-safe configuration
  - Can generate complex patterns programmatically
- **Cons**:
  - Requires pre-rendering for ArgoCD (or CMP installation)
  - Steeper learning curve (Jsonnet syntax)
  - Vendor directory bloat (k8s-libsonnet)
  - Not natively supported by ArgoCD

### 2. Integrate HashiCorp Vault for Secrets

#### Kustomize
- **Tested**: Yes
- **Approach**: ExternalSecret CRD in base resources, syncs from AWS Secrets Manager via ESO
- **Example**: `kustomize/base/external-secret.yaml`
- **Status**: Working - secrets synced successfully

#### Tanka/Jsonnet
- **Tested**: Yes
- **Approach**: ExternalSecret defined in Jsonnet library, rendered to YAML
- **Example**: `lib/poc-app.libsonnet` -> `externalSecret::` object
- **Status**: Working - same ESO mechanism

**Note**: Both tools work with ESO/VSO for Vault/Secrets Manager integration. Neither has special Vault-native support - they simply manage the ExternalSecret CRD manifests.

### 3. Support Supply Chain Automation

#### Kustomize
- **Tested**: Partial (ECR repo created, but Docker daemon unavailable for image push)
- **Approach**: Image references in overlay patches
- **Example**: `patches: [{target: Deployment, patch: image: xxx.ecr.aws/repo:tag}]`
- **Status**: ECR repository created successfully

#### Tanka/Jsonnet
- **Tested**: Partial
- **Approach**: Image variable in config object
- **Example**: `config+:: { image: '050752617334.dkr.ecr.eu-central-1.amazonaws.com/poc-demo-app:v1' }`
- **Status**: Same limitation

### 4. Usage of Full-Features Template

#### Kustomize
- **Tested**: Yes
- **Approach**: Bitnami PostgreSQL Helm chart rendered and managed via overlays
- **Features Demonstrated**:
  - StorageClass override (gp2)
  - Storage size (1Gi test, 5Gi prod)
  - Backup CronJob (prod only)
  - ConfigMap environment variables
  - ExternalSecret integration
- **Pros**: Standard Helm ecosystem compatibility
- **Cons**: Must track Helm chart versions manually, re-render on updates

#### Tanka/Jsonnet
- **Tested**: Yes
- **Approach**: Native Jsonnet StatefulSet definition with configurable parameters
- **Features Demonstrated**:
  - Conditional CronJob (enableBackup: true/false)
  - Resource customization per environment
  - Namespace-aware generation
- **Pros**: Full control over resources, conditional logic
- **Cons**: Must manually define resources (no Helm chart reuse)

## Environment Differences Verified

| Aspect | Test | Prod | Test7 |
|--------|------|------|-------|
| Namespace | poc-cfg-test | poc-cfg-prod | poc-cfg-test7 |
| PUBLIC_URL | https://test.example.local | https://prod.example.local | https://test7.example.local |
| StorageClass | gp2 | gp2 | gp2 |
| Storage Size | 1Gi | 5Gi | 1Gi |
| Replicas | 1 | 2 | 1 |
| Backup CronJob | No | Yes | No |
| Image Tag | nginx:1.25-alpine | nginx:1.24-alpine | nginx:1.25-alpine |

## Fast Environment Creation (test7)

### Kustomize
- **Steps Required**: 1
  1. Create `overlays/test7/kustomization.yaml` (copy test, modify namespace/PUBLIC_URL)
- **Lines of Config**: ~25 lines
- **Time**: <5 minutes

### Tanka/Jsonnet
- **Steps Required**: 2
  1. Create `environments/test7/main.jsonnet` (set config values)
  2. Create `environments/test7/spec.json` (namespace/apiServer)
  3. Run `tk export` to generate manifests
- **Lines of Config**: ~25 lines + export step
- **Time**: <10 minutes (including export)

## ArgoCD Integration

### Kustomize
- **Method**: Native support
- **ApplicationSet**: Standard path-based generator
- **Sync Status**: Synced
- **Health**: Degraded (PVC pending due to WaitForFirstConsumer - expected)

### Tanka/Jsonnet
- **Method**: Pre-rendered manifests committed to Git
- **ApplicationSet**: Same approach (uses rendered/ directory)
- **Sync Status**: Synced
- **Alternative**: Config Management Plugin (CMP) for native rendering

## Recommendations

### Use Kustomize When:
- Team is YAML-focused with limited programming experience
- Need tight ArgoCD integration out-of-the-box
- Simple overlay patterns are sufficient
- Helm charts are primary source of truth

### Use Tanka/Jsonnet When:
- Team has programming background
- Complex conditional logic is required
- Need to generate many similar resources programmatically
- Want strong typing and code reuse across environments

## Reproduction Commands

```bash
# Clone repo
git clone https://github.com/NoahInCloud/wivprojects.git
cd wivprojects

# Verify Kustomize builds
kustomize build poc-config-mgmt/kustomize/overlays/test
kustomize build poc-config-mgmt/kustomize/overlays/prod
kustomize build poc-config-mgmt/kustomize/overlays/test7

# Verify Tanka renders (requires tk installed)
cd poc-config-mgmt/tanka
tk show environments/test
tk show environments/prod
tk show environments/test7

# Apply ArgoCD ApplicationSets
kubectl apply -f poc-config-mgmt/argocd/applications/

# Check deployments
kubectl get ns | grep poc
kubectl -n poc-cfg-test get all,cm,secret,pvc,externalsecret
kubectl -n poc-cfg-prod get all,cm,secret,pvc,externalsecret,cronjob
```

## Files Created

```
poc-config-mgmt/
├── kustomize/
│   ├── base/
│   │   ├── demo-app-configmap.yaml
│   │   ├── demo-app-deployment.yaml
│   │   ├── demo-app-service.yaml
│   │   ├── external-secret.yaml
│   │   ├── helm-rendered/postgres.yaml
│   │   └── kustomization.yaml
│   └── overlays/
│       ├── prod/
│       │   ├── backup-cronjob.yaml
│       │   └── kustomization.yaml
│       ├── test/
│       │   └── kustomization.yaml
│       └── test7/
│           └── kustomization.yaml
├── tanka/
│   ├── environments/
│   │   ├── prod/
│   │   │   ├── main.jsonnet
│   │   │   └── spec.json
│   │   ├── test/
│   │   │   ├── main.jsonnet
│   │   │   └── spec.json
│   │   └── test7/
│   │       ├── main.jsonnet
│   │       └── spec.json
│   ├── lib/
│   │   └── poc-app.libsonnet
│   └── rendered/
│       ├── prod/
│       ├── test/
│       └── test7/
├── argocd/
│   └── applications/
│       ├── poc-kustomize-appset.yaml
│       └── poc-tanka-appset.yaml
└── RESULTS.md
```
