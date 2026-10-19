# Taller Kubernetes avanzado: Saludos en Amazon EKS con red existente y RDS

Este taller despliega una aplicación de ejemplo **frontend + backend** sobre Amazon EKS, reutilizando una VPC y recursos de red existentes y utilizando **Amazon RDS PostgreSQL** como base de datos. El ejercicio está pensado para practicar Kubernetes sobre una infraestructura administrada, sin convertir el taller en una práctica de creación de VPC desde cero.

La aplicación se organiza de forma que:

```text
                    Administrador
                         |
                         | kubectl / K9s
                         v
                    EKS API Server
                         |
             +-----------+-----------+
             |                       |
        Frontend Service        Backend Service
          (ClusterIP)              (ClusterIP)
             |                       |
       Frontend Pods             Backend Pods
                                      |
                                      | TCP 5432
                                      v
                                RDS PostgreSQL
```

> **Importante:** en esta primera versión el frontend se expone para pruebas mediante `kubectl port-forward`. El paso posterior del taller puede evolucionar a **Ingress + AWS Load Balancer Controller**, permitiendo compartir un Load Balancer entre varias aplicaciones/namespaces.

---

## Estructura del taller

```text
k8s_avanzado/
├── 01-eks-rds/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── versions.tf
│   └── terraform.tfvars.example
│
├── 02-namespace/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── versions.tf
│
├── yamls/
│   ├── application/
│   │   ├── backend-deployment.yaml
│   │   ├── backend-service.yaml
│   │   ├── frontend-deployment.yaml
│   │   ├── frontend-service.yaml
│   │   └── saludos-db-config.yaml
│   │
│   └── database-template/
│       └── saludos-db-secret.example
│
└── README.md
```

### Responsabilidad de cada parte

- `01-eks-rds/`: consulta infraestructura de red existente y crea EKS, el Managed Node Group y RDS.
- `02-namespace/`: crea el Namespace en un estado Terraform separado.
- `yamls/application/`: despliega frontend, backend, Services y ConfigMap.
- `yamls/database-template/`: contiene la plantilla del Secret de PostgreSQL.
- `service_discovery/db/init.sql` del proyecto general: contiene el esquema y datos iniciales de la aplicación original basada en Docker Compose.

---

# 0. Conceptos importantes antes de comenzar

## Infraestructura compartida vs. recursos de Kubernetes

Crear un Namespace **no crea nuevos nodos ni un nuevo cluster**. Varios estudiantes pueden utilizar el mismo EKS:

```text
EKS
├── namespace estudiante01
│   ├── frontend
│   └── backend
├── namespace estudiante02
│   ├── frontend
│   └── backend
└── namespace estudiante03
    ├── frontend
    └── backend
```

Los recursos del Namespace son copias lógicas de los objetos Kubernetes de la aplicación. Todos pueden compartir los mismos nodos mientras las políticas y los recursos lo permitan.

En esta etapa los Services son `ClusterIP`, por lo que **no se crea un Load Balancer de AWS por estudiante**. Para una futura exposición externa se recomienda usar un único Ingress/ALB con reglas por host o ruta.

## Service Discovery en Kubernetes

El backend tiene un Service llamado `saludos-backend`. Por eso el frontend puede utilizar:

```text
http://saludos-backend:5000
```

La resolución se realiza mediante el DNS interno de Kubernetes:

```text
Frontend Pod
   |
   | DNS
   v
saludos-backend
   |
   v
Service ClusterIP
   |
   v
Backend Pod(s)
```

No se debe configurar el frontend con la IP de un Pod, porque las IP de los Pods son efímeras.

---

# 1. Prerrequisitos

Antes de ejecutar el taller se requiere:

- AWS CLI configurado con permisos suficientes para EKS, EC2, IAM y RDS.
- Terraform >= 1.5.7.
- `kubectl`.
- K9s es opcional, pero recomendado para observar el cluster.
- Docker para construir y publicar las imágenes.
- Acceso a una VPC existente con subnets públicas y privadas.
- Un NAT Gateway `available` para las subnets privadas, o conectividad equivalente mediante VPC endpoints.
- `psql` opcional en la máquina administrativa. También puede utilizarse un contenedor temporal con `postgres:16` dentro del cluster.

---

# 2. Verificar la red existente

Este proyecto **no crea la VPC, las subnets, el Internet Gateway ni el NAT Gateway**. Terraform los consulta mediante `data`.

La topología mínima esperada es:

```text
                         Internet
                            |
                    Internet Gateway
                            |
                       Public Subnet
                            |
                       NAT Gateway
                            |
                    Private Route Table
                            |
              +-------------+-------------+
              |                           |
        Private Subnet A            Private Subnet B
          us-east-1a                  us-east-1d
              |                           |
              +-------------+-------------+
                            |
                         EKS/RDS
```

Las subnets privadas usadas por el Node Group deben estar en **AZ distintas**. En la práctica utilizada para este taller:

```text
subnet-084a399477ee4e697 -> us-east-1a
subnet-0163f0f24282a7c93 -> us-east-1d
```

Compruébalas con:

```bash
aws ec2 describe-subnets \
  --region us-east-1 \
  --subnet-ids subnet-0163f0f24282a7c93 subnet-084a399477ee4e697 \
  --query 'Subnets[].{SubnetId:SubnetId,AZ:AvailabilityZone,Cidr:CidrBlock}' \
  --output table
```

Y revisa que las route tables privadas tengan salida al NAT:

```bash
aws ec2 describe-route-tables \
  --region us-east-1 \
  --filters \
    "Name=association.subnet-id,Values=subnet-0163f0f24282a7c93,subnet-084a399477ee4e697" \
  --query 'RouteTables[].{RouteTableId:RouteTableId,Routes:Routes[].{Destination:DestinationCidrBlock,GatewayId:GatewayId,NatGatewayId:NatGatewayId,State:State}}' \
  --output json
```

Debe existir una ruta equivalente a:

```text
0.0.0.0/0 -> nat-04b3c4a1c81af3090
```

---

# 3. Configurar 01-eks-rds

```bash
cd 01-eks-rds
cp terraform.tfvars.example terraform.tfvars
```

Edita `terraform.tfvars` con los IDs reales.

Ejemplo del bloque de acceso público al API de EKS:

```hcl
cluster_endpoint_public_access_cidrs = [
  "TU_IP_PUBLICA/32",
  "IP_PUBLICA_DE_LA_NAT/32"
]
```

### ¿Por qué agregar la IP de la NAT?

Los nodos de las subnets privadas pueden salir mediante la NAT Gateway. Si la inicialización del nodo llega al **endpoint público** de EKS, el origen visible para el endpoint será la IP pública de la NAT, no la IP pública del portátil.

En la práctica comprobada en este taller:

```text
Laptop administrativa
190.27.74.29
      |
      +----> EKS API público

Nodo privado
      |
      v
NAT Gateway
54.80.183.252
      |
      +----> EKS API público
```

Por eso la whitelist utilizada fue:

```hcl
cluster_endpoint_public_access_cidrs = [
  "190.27.74.29/32",
  "54.80.183.252/32"
]
```

> No uses `0.0.0.0/0` para el laboratorio.

El endpoint privado también puede mantenerse habilitado:

```hcl
endpoint_private_access = true
endpoint_public_access  = true
```

---

# 4. Configuración del Node Group

Para este laboratorio se utilizan **dos nodos**, uno por cada subnet privada/AZ.

Se recomienda utilizar al menos:

```hcl
node_instance_types = ["t3.small"]
node_count          = 2
```

## ¿Por qué no `t3.micro`?

Durante la práctica, con `t3.micro` Kubernetes llegó a mostrar:

```text
0/2 nodes are available: 2 Too many pods.
```

Los nodos estaban en estado `Ready`, pero su capacidad asignable de Pods era insuficiente para convivir con los Pods del sistema y las réplicas de frontend/backend.

Por eso se cambió a `t3.small`, manteniendo dos nodos en AZ distintas.

Comprueba la capacidad después del despliegue:

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,PODS:.status.allocatable.pods,CPU:.status.allocatable.cpu,MEM:.status.allocatable.memory
```

## No reutilizar el Security Group de RDS para los nodos

El SG de RDS y el SG de los nodos cumplen funciones diferentes:

```text
SG de nodos EKS -> tráfico de los nodos y componentes de Kubernetes
SG de RDS       -> tráfico hacia PostgreSQL
```

No adjuntes el SG de la base de datos a los nodos como SG del Node Group. Para RDS, la regla deseada es la dirección inversa: **el SG de RDS permite TCP/5432 desde el SG de los nodos**.

---

# 5. KMS y CloudWatch

Para este taller no es necesario añadir una CMK propia para EKS ni crear un log group adicional de CloudWatch solo para poder desplegar la aplicación.

Con la versión utilizada del módulo EKS, evita forzar una configuración vacía de `encryption_config` junto con `create_kms_key = false`, porque el módulo puede interpretar que se está solicitando configuración de cifrado y exigir un `key_arn`.

La configuración de CloudWatch puede desactivarse con:

```hcl
create_cloudwatch_log_group = false
enabled_log_types           = []
```

El objetivo del taller es Kubernetes/EKS, no la administración de una CMK ni la operación de logs del control plane.

---

# 6. Crear EKS y RDS

Ejecuta:

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply -var-file="./terraform.tfvars.example"
```

Después verifica el cluster:

```bash
aws eks describe-cluster \
  --region us-east-1 \
  --name diplomado-k8s \
  --query 'cluster.status'
```

Debe aparecer:

```text
"ACTIVE"
```

---

# 7. Conectar `kubectl` a EKS

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name diplomado-k8s
```

Comprueba el contexto:

```bash
kubectl config current-context
```

Y los nodos:

```bash
kubectl get nodes -o wide
```

También puedes revisar las etiquetas que permiten seleccionar los nodos de la aplicación:

```bash
kubectl get nodes -L environment -L workload
```

Los nodos deben tener:

```text
environment=development
```

---

# 8. Usar K9s

K9s se ejecuta **fuera del cluster** y utiliza el mismo contexto de `kubectl`.

```bash
k9s
```

Comandos útiles dentro de K9s:

```text
:nodes   -> nodos
:pods    -> Pods
:svc     -> Services
:deploy  -> Deployments
:ns      -> Namespaces
```

No se instala K9s en los nodos EKS.

---

# 9. Crear el Namespace

En `02-namespace`:

```bash
cd ../02-namespace
cp terraform.tfvars.example terraform.tfvars
```

Edita:

```hcl
namespace_name = "brendisas"
```

Cada estudiante puede utilizar su propio nombre de Namespace:

```text
brendisas
estudiante01
estudiante02
estudiante03
```

Luego:

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Verifica:

```bash
kubectl get namespaces
```

> **Importante:** los YAML de esta carpeta tienen inicialmente `namespace: saludos-dev`. Si el Namespace creado tiene otro nombre, cambia ese valor de manera consistente en todos los manifiestos antes de aplicar la aplicación.

---

# 10. Preparar las imágenes Docker

Las imágenes del laboratorio original se construyen desde `service_discovery`.

Supongamos que tienes:

```text
saludos-backend:1.0
saludos-frontend:1.0
```

Si tu usuario de Docker Hub es `brendisas`:

```bash
docker tag saludos-backend:1.0 brendisas/backend:1.0
docker tag saludos-frontend:1.0 brendisas/frontend:1.0
```

Publícalas:

```bash
docker push brendisas/backend:1.0
docker push brendisas/frontend:1.0
```

En los Deployment:

```yaml
image: brendisas/backend:1.0
```

```yaml
image: brendisas/frontend:1.0
```

## Error común: frontend y backend con el mismo digest

Durante la práctica se encontró un caso en el que Kubernetes mostraba:

```text
Image:    brendisas/frontend:1.0
Image ID: docker.io/brendisas/backend@sha256:...
```

Esto significa que el tag `frontend:1.0` en el registry estaba apuntando a la imagen equivocada.

Verifica los digests:

```bash
docker pull brendisas/frontend:1.0
docker image inspect brendisas/frontend:1.0 --format '{{index .RepoDigests 0}}'

docker pull brendisas/backend:1.0
docker image inspect brendisas/backend:1.0 --format '{{index .RepoDigests 0}}'
```

Los digests deben ser diferentes.

Para depuración, puedes usar:

```yaml
imagePullPolicy: Always
```

pero para el material definitivo es preferible usar **tags versionados e inmutables**, por ejemplo `1.0`, `1.1`, `1.2`, en lugar de sobrescribir repetidamente `1.0`.

---

# 11. ConfigMap y Secret de la base de datos

La aplicación ya tiene la separación correcta:

```text
ConfigMap
├── DB_HOST
├── DB_PORT
└── DB_NAME

Secret
├── DB_USER
└── DB_PASSWORD
```

El backend carga ambos con:

```yaml
envFrom:
  - configMapRef:
      name: saludos-db-config
  - secretRef:
      name: saludos-db-secret
```

## 11.1 Obtener el endpoint de RDS

Desde `01-eks-rds`:

```bash
cd ../01-eks-rds
terraform output rds_endpoint
terraform output rds_database_name
```

Copia el endpoint en `yamls/application/saludos-db-config.yaml`:

```yaml
data:
  DB_HOST: "SALUDOS_POSTGRES_ENDPOINT"
  DB_PORT: "5432"
  DB_NAME: "saludos"
```

**`DB_HOST` no es `saludos` ni `saludos-backend`.** El primero es el nombre de la base; el segundo es el nombre del Service de Kubernetes.

## 11.2 Crear el Secret

Copia la plantilla:

```bash
cp ../yamls/database-template/saludos-db-secret.example \
   ../yamls/application/saludos-db-secret.yaml
```

Edita el archivo y coloca la misma contraseña utilizada por RDS:

```yaml
stringData:
  DB_USER: "saludos_admin"
  DB_PASSWORD: "LA_CONTRASENA_REAL"
```

No subas credenciales reales al repositorio.

---

# 12. Seguridad de RDS

La RDS se mantiene privada:

```hcl
publicly_accessible = false
```

Por eso **no puedes conectarte directamente a ella desde tu laptop por Internet**, aunque agregues la IP del laptop al Security Group.

La conectividad correcta es:

```text
Backend Pod
    |
    | TCP 5432
    v
Node / VPC
    |
    v
RDS privada
```

## Regla del Security Group de RDS

El Security Group de RDS debe permitir:

```text
Protocol: TCP
Port:     5432
Source:   Security Group de los nodos EKS
```

No uses `0.0.0.0/0`.

En la práctica comprobada:

```text
SG nodos: sg-08c959aa3f9345e2f
SG RDS:   sg-05a8690695d147e52
```

Regla conceptual:

```text
sg-08c959aa3f9345e2f -> TCP/5432 -> sg-05a8690695d147e52
```

---

# 13. Verificar conectividad antes de culpar a Kubernetes

Desde el Pod del backend se comprobó conectividad TCP con Python:

```bash
python -c "import socket; print(socket.create_connection(('SALUDOS_RDS_ENDPOINT', 5432), 5))"
```

Una salida como:

```text
<socket.socket ... raddr=('10.0.0.100', 5432)>
```

confirma que el backend puede establecer la conexión TCP con PostgreSQL.

Si no tienes `nc` en la imagen, no es necesario modificarla únicamente para esta prueba.

---

# 14. Inicializar la RDS con el esquema y los datos de la aplicación

La RDS creada por Terraform contiene la base de datos `saludos`, pero **crear la base no crea automáticamente las tablas ni los datos de la aplicación**.

En el proyecto general, el SQL original está en:

```text
service_discovery/db/init.sql
```

Ese archivo crea la tabla `saludos` e inserta los mensajes iniciales.

Por eso, después de crear la RDS hay que inicializar el esquema.

## Opción recomendada para el taller: cliente PostgreSQL temporal dentro del cluster

Como RDS es privada, la forma sencilla de acceder durante el laboratorio es ejecutar un Pod temporal dentro del mismo cluster:

```bash
kubectl run psql-client \
  -n NOMBRE_DEL_NAMESPACE \
  --rm -it \
  --image=postgres:16 \
  -- bash
```

Dentro del contenedor:

```bash
psql \
  -h SALUDOS_RDS_ENDPOINT \
  -p 5432 \
  -U saludos_admin \
  -d saludos
```

Escribe la contraseña.

Una vez dentro de `psql`:

```sql
\dt
```

Si devuelve:

```text
Did not find any relations.
```

la base está conectada pero **todavía no tiene tablas**.

## Cargar `init.sql`

Desde tu máquina copia el archivo al Pod temporal:

```bash
kubectl cp /ruta/al/repositorio/service_discovery/db/init.sql \
  NOMBRE_DEL_NAMESPACE/<NOMBRE_DEL_POD>:/tmp/init.sql
```

Después entra al cliente y conéctate a PostgreSQL.

Dentro de `psql`:

```sql
\i /tmp/init.sql
```

Comprueba:

```sql
\dt
SELECT * FROM saludos;
```

Deberías tener la tabla y los mensajes iniciales.

> **Mejora futura:** esta inicialización puede automatizarse con Terraform o con un Job de Kubernetes. Para una primera práctica, mantenerla como paso explícito ayuda a enseñar la diferencia entre **provisionar infraestructura** e **inicializar datos**.

---

# 15. Aplicar los YAML de la aplicación

Verifica primero que existan el ConfigMap y el Secret:

```bash
kubectl get configmap -n NOMBRE_DEL_NAMESPACE
kubectl get secret -n NOMBRE_DEL_NAMESPACE
```

Después:

```bash
kubectl apply -f ../yamls/application/
```

Comprueba:

```bash
kubectl get pods -n NOMBRE_DEL_NAMESPACE -o wide
kubectl get svc -n NOMBRE_DEL_NAMESPACE
kubectl get deployments -n NOMBRE_DEL_NAMESPACE
```

---

# 16. Problema de scheduling: `Too many pods`

Si aparece:

```text
0/2 nodes are available: 2 Too many pods.
```

no significa necesariamente que los nodos estén caídos. Los nodos pueden estar `Ready` y, aun así, no tener capacidad asignable de Pods suficiente.

Diagnóstico:

```bash
kubectl describe pod NOMBRE_DEL_POD -n NOMBRE_DEL_NAMESPACE
```

Revisa la sección `Events`.

También:

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,PODS:.status.allocatable.pods,CPU:.status.allocatable.cpu,MEM:.status.allocatable.memory
```

Para este taller se recomienda `t3.small` en lugar de `t3.micro`.

No elimines `replicas: 2` solo para ocultar el problema: las dos réplicas y la distribución entre nodos forman parte de la práctica.

---

# 17. Verificar el frontend y backend

## Backend

```bash
kubectl get pods -n NOMBRE_DEL_NAMESPACE -l app=saludos,component=backend -o wide
kubectl get endpoints saludos-backend -n NOMBRE_DEL_NAMESPACE -o wide
```

El Service debe tener endpoints.

## Frontend

```bash
kubectl get pods -n NOMBRE_DEL_NAMESPACE -l app=saludos,component=frontend -o wide
```

En los Pods del frontend, el contenedor debe tener la imagen del frontend y no la del backend.

Compruébalo con:

```bash
kubectl describe pod NOMBRE_DEL_POD -n NOMBRE_DEL_NAMESPACE
```

Debe verse algo equivalente a:

```text
Image:    brendisas/frontend:1.0
Image ID: docker.io/brendisas/frontend@sha256:...
```

---

# 18. Probar el backend desde el frontend

Puedes entrar al frontend:

```bash
kubectl exec -it NOMBRE_DEL_POD_FRONTEND -n NOMBRE_DEL_NAMESPACE -- sh
```

Y probar:

```bash
curl -v http://saludos-backend:5000/saludo
```

Una salida donde aparezca:

```text
Host saludos-backend:5000 was resolved.
Trying 172.x.x.x:5000...
Established connection...
```

demuestra que DNS, Service y conectividad TCP están funcionando.

Si el backend responde `500`, entonces el problema está en la aplicación o la base de datos, no en el Service Discovery.

---

# 19. Probar el frontend desde el navegador

El Service del frontend es actualmente:

```yaml
type: ClusterIP
```

Por eso no tiene una IP pública.

Usa:

```bash
kubectl port-forward service/saludos-frontend 8080:80 -n NOMBRE_DEL_NAMESPACE
```

Luego abre:

```text
http://localhost:8080
```

La ruta es:

```text
Navegador
   |
   v
localhost:8080
   |
   v
saludos-frontend Service
   |
   v
Frontend Pods
   |
   v
saludos-backend:5000
   |
   v
Backend Pods
   |
   v
RDS PostgreSQL
```

La terminal del `port-forward` debe permanecer abierta mientras se realiza la prueba.

---

# 20. Diagnóstico rápido de errores

## `ImagePullBackOff` / `ErrImagePull`

Verifica:

```bash
kubectl describe pod NOMBRE_DEL_POD -n NOMBRE_DEL_NAMESPACE
```

Comprueba que:

- el repositorio exista;
- el tag exista;
- la imagen no sea privada sin credenciales;
- el `image` del Deployment sea el correcto.

## El frontend muestra Flask en lugar de Nginx

Revisa:

```bash
kubectl describe pod NOMBRE_DEL_POD -n NOMBRE_DEL_NAMESPACE
```

Si aparece:

```text
Image:    brendisas/frontend:1.0
Image ID: docker.io/brendisas/backend@sha256:...
```

el tag del frontend en el registry está asociado a la imagen equivocada. Corrige la imagen y vuelve a publicar.

## Frontend responde `504 upstream timed out`

Primero comprueba:

```bash
kubectl get svc saludos-backend -n NOMBRE_DEL_NAMESPACE -o wide
kubectl get endpoints saludos-backend -n NOMBRE_DEL_NAMESPACE -o wide
```

Después prueba desde el frontend:

```bash
curl -v http://saludos-backend:5000/saludo
```

Si la conexión TCP se establece pero el backend devuelve `500`, revisa:

```bash
kubectl logs deployment/saludos-backend -n NOMBRE_DEL_NAMESPACE
```

Una causa común en esta práctica es que la RDS tenga la base creada pero todavía no tenga la tabla `saludos`.

## `0/2 nodes are available: Too many pods`

Aumenta el tamaño de los nodos a `t3.small` y verifica el `allocatable.pods`.

## No puedo conectarme con `psql` desde mi laptop

Es esperado si RDS permanece:

```hcl
publicly_accessible = false
```

Accede desde un recurso dentro de la VPC, como un Pod temporal en EKS.

---

# 21. Orden recomendado para cada estudiante

```text
1. Verificar VPC, subnets, NAT y route tables
        |
2. terraform apply en 01-eks-rds
        |
3. aws eks update-kubeconfig
        |
4. kubectl get nodes
        |
5. Crear Namespace con 02-namespace
        |
6. Crear ConfigMap y Secret
        |
7. Publicar imágenes Docker
        |
8. Inicializar RDS con init.sql
        |
9. kubectl apply -f yamls/application/
        |
10. kubectl get pods / svc / endpoints
        |
11. Probar backend desde frontend
        |
12. kubectl port-forward frontend
        |
13. Abrir http://localhost:8080
```

---

# 22. Limpieza

Primero elimina el Namespace desde `02-namespace`:

```bash
cd 02-namespace
terraform destroy
```

Después destruye EKS y RDS:

```bash
cd ../01-eks-rds
terraform destroy
```

Los recursos consultados mediante `data` (VPC, subnets, route tables, IGW y NAT) no son creados ni destruidos por este proyecto.

> `skip_final_snapshot = true` facilita el laboratorio, pero significa que la RDS puede eliminarse sin snapshot final. No uses esta opción como patrón para una base productiva sin revisar los requisitos de recuperación.

---

# 23. Extensión avanzada: un solo Load Balancer para varios Namespaces

La versión base utiliza `ClusterIP + port-forward` para evitar crear un Load Balancer por estudiante.

Una evolución natural es:

```text
                         Internet
                            |
                            v
                   Un solo ALB / Ingress
                            |
              +-------------+-------------+
              |             |             |
           /est01        /est02        /est03
              |             |             |
           Service       Service       Service
              |             |             |
           Frontend      Frontend      Frontend
```

Otra opción es utilizar hosts:

```text
est01.ejemplo.com
est02.ejemplo.com
est03.ejemplo.com
```

Esto permite enseñar que **Namespace no implica Load Balancer propio** y abre la puerta a tratar multi-tenancy, Ingress, routing y compartición de infraestructura.