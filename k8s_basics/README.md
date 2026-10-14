# 🧪 Laboratorio: Primeros pasos con Kubernetes usando kubectl

## 1. 🔍 Verificar el entorno y el clúster

```bash
kubectl version --client
kubectl config current-context
kubectl cluster-info
kubectl get nodes
kubectl get nodes -o wide
```

## 2. 📚 Explorar recursos y documentación

```bash
kubectl api-resources
kubectl explain deployment
kubectl explain deployment.spec
kubectl get pods -A
kubectl describe nodes
```

## 3. 🗂️ Consultar namespaces

```bash
kubectl get namespaces
kubectl get pods -n kube-system
kubectl get pods -A
kubectl get configmaps -n kube-public
```

## 4. 🔀 Explorar y crear contextos

### Consultar los contextos disponibles

```bash
kubectl config current-context
kubectl config get-contexts
```

### Crear un namespace para el laboratorio

```bash
kubectl create namespace laboratorio
```

### Crear un contexto de laboratorio

Reemplaza `microk8s` por los nombres reales de tu configuración.

```bash
kubectl config set-context lab-context \
  --cluster=microk8s \
  --user=microk8s \
  --namespace=default

kubectl config set-context lab-context-ns \
  --cluster=microk8s \
  --user=microk8s \
  --namespace=laboratorio
```

### Cambiar de contexto y verificar el namespace

```bash
kubectl config use-context lab-context-ns
kubectl config current-context
kubectl config get-contexts
kubectl get pods
kubectl get pods -n default
```

### Volver al contexto original

```bash
kubectl config use-context <contexto-original>
```

## 5. 🚀 Crear el primer Deployment

```bash
kubectl create deployment web --image=nginx -n default
kubectl get deployments -n default
kubectl get replicasets -n default
kubectl get pods -n default
kubectl describe deployment web -n default
kubectl get pods -o wide -n default
```

## 6. 📋 Consultar información, eventos y logs

```bash
kubectl get pods -n default
kubectl describe pod <nombre-del-pod> -n default
kubectl logs deployment/web --tail=20 -n default
kubectl logs <nombre-del-pod> -n default
kubectl get events -n default --sort-by=.metadata.creationTimestamp
```

## 7. 📈 Escalar y observar la recuperación de Pods

### Escalar a tres réplicas

```bash
kubectl scale deployment/web --replicas=3 -n default
kubectl get deployments -n default
kubectl get pods -n default
```

### Observar los cambios

```bash
kubectl get pods --watch -n default
```

### Eliminar un Pod y observar su recuperación

```bash
kubectl get pods -n default
kubectl delete pod <nombre-del-pod> -n default
kubectl get pods --watch -n default
```

## 8. ⚙️ Crear y consultar un ConfigMap

```bash
kubectl create configmap app-config \
  --from-literal=APP_ENV=lab \
  -n default

kubectl get configmaps -n default
kubectl describe configmap app-config -n default
```

## 9. 🔐 Crear y consultar un Secret

```bash
kubectl create secret generic app-secret \
  --from-literal=API_TOKEN=demo123 \
  -n default

kubectl get secrets -n default
kubectl describe secret app-secret -n default
```

> ⚠️ Utiliza únicamente valores ficticios.

## 10. 🌐 Crear un Service interno para NGINX

### Verificar el Deployment

```bash
kubectl get deployments -n default
kubectl get pods -n default
```

### Crear el Service de tipo ClusterIP

```bash
kubectl expose deployment web \
  --name=web-interno \
  --port=80 \
  --target-port=80 \
  --type=ClusterIP \
  -n default
```

### Verificar el Service y sus endpoints

```bash
kubectl get services -n default
kubectl get endpoints web-interno -n default
kubectl get endpointslices -n default
```

### Probar el acceso interno con curl

```bash
curl http://<IPs:port>
```

## 11. 🧹 Limpiar los recursos creados

### Eliminar el Service y el Deployment

```bash
kubectl delete service web-interno -n default
kubectl delete deployment web -n default
```

### Eliminar el ConfigMap y el Secret

```bash
kubectl delete configmap app-config -n default
kubectl delete secret app-secret -n default
```

### Eliminar el namespace de laboratorio

```bash
kubectl delete namespace laboratorio
```

### Eliminar los contextos de prueba

Primero, asegúrate de volver al contexto original.

```bash
kubectl config use-context <contexto-original>
kubectl config delete-context lab-context
kubectl config delete-context lab-context-ns
```

### Verificar la limpieza

```bash
kubectl get deployments -n default
kubectl get services -n default
kubectl get configmaps -n default
kubectl get secrets -n default
kubectl config get-contexts
```