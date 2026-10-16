# Instalación local — prerrequisito de la Práctica 8

Todo esto corre en tu máquina, no en GitHub Actions (el pipeline nunca
toca el clúster — ver el porqué en `README.md`). Instálalo una sola
vez; el clúster de `kind` lo vas a mantener encendido mientras
trabajas y durante la calificación.

## 1. Herramientas nuevas que no tenías en P5/P6/P7

```powershell
winget install -e --id Kubernetes.kind
winget install -e --id Hashicorp.Terraform
winget install -e --id Aquasecurity.Trivy
```

**Cosign** no tiene paquete de `winget` confiable a la fecha; descarga el binario:

```powershell
Invoke-WebRequest -Uri "https://github.com/sigstore/cosign/releases/latest/download/cosign-windows-amd64.exe" -OutFile "$env:USERPROFILE\cosign.exe"
Move-Item "$env:USERPROFILE\cosign.exe" "C:\Windows\System32\cosign.exe"
cosign version
```

**El plugin de `kubectl` para Argo Rollouts** (para ver el estado del
canary desde la terminal):

```powershell
Invoke-WebRequest -Uri "https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-windows-amd64.exe" -OutFile "$env:USERPROFILE\kubectl-argo-rollouts.exe"
Move-Item "$env:USERPROFILE\kubectl-argo-rollouts.exe" "C:\Windows\System32\kubectl-argo-rollouts.exe"
kubectl argo rollouts version
```

**El CLI de ArgoCD**:

```powershell
Invoke-WebRequest -Uri "https://github.com/argoproj/argo-cd/releases/latest/download/argocd-windows-amd64.exe" -OutFile "$env:USERPROFILE\argocd.exe"
Move-Item "$env:USERPROFILE\argocd.exe" "C:\Windows\System32\argocd.exe"
argocd version --client
```

Cierra y vuelve a abrir PowerShell después de estos pasos.

## 2. Crear el clúster de kind

```powershell
kind create cluster --name aroma-p8
kubectl cluster-info --context kind-aroma-p8
```

## 3. Aplicar Terraform (namespaces, cuotas, límites, RBAC)

```powershell
cd P8\terraform
terraform init
terraform plan -out=plan.tfout
terraform apply plan.tfout
```

Verifica:

```powershell
kubectl get namespaces aroma-staging aroma-prod
kubectl get resourcequota,limitrange,role,rolebinding -n aroma-prod
```

**Esto es la primera evidencia real que necesitas**: guarda la salida
de `terraform plan` y de `terraform apply` (capturas o el texto), es
el entregable "Código Terraform ... con evidencia de plan y apply".

## 4. Instalar ArgoCD, Argo Rollouts y Kyverno dentro del clúster

```powershell
# ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Argo Rollouts
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# Kyverno
kubectl create namespace kyverno
kubectl apply -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml
```

Dale 1-2 minutos y confirma que todo esté arriba:

```powershell
kubectl get pods -n argocd
kubectl get pods -n argo-rollouts
kubectl get pods -n kyverno
```

## 5. Entrar al panel de ArgoCD (opcional pero útil para la demo)

```powershell
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Usuario `admin`, contraseña:

```powershell
$pass = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($pass))
```

Abre `https://localhost:8080` (certificado autofirmado, el navegador
va a advertir — es normal en un clúster local).

---

Corre esto y pégame la salida de `terraform plan`/`terraform apply` y
de los tres `kubectl get pods` — con eso confirmamos que la base está
sana antes de seguir con los charts de Helm y las `Application` de
ArgoCD, que es la siguiente capa.
