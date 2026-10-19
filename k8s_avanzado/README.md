# Taller Kubernetes avanzado: Saludos en Amazon EKS con red existente y RDS

Este proyecto reutiliza una VPC y sus recursos de red existentes mediante `data` de Terraform. Crea EKS con dos nodos de trabajo y una base de datos RDS PostgreSQL privada. El Namespace y los manifiestos de la aplicación se gestionan por separado.

## Estructura

- `01-eks-rds/`: consulta VPC, subnets, route tables, Internet Gateway, NAT Gateway y Security Groups existentes; crea EKS, un Managed Node Group de dos nodos y RDS PostgreSQL.
- `02-namespace/`: se conecta al EKS existente y crea un Namespace configurable.
- `yamls/application/`: Deployment y Service de frontend/backend y ConfigMap de conexión a RDS.
- `yamls/database-template/saludos-db-secret.example`: plantilla de Kubernetes Secret. No la apliques hasta reemplazar el valor de contraseña.

## Qué se consulta y qué se crea

Se consultan con `data`:
- La VPC existente.
- Los IDs de las subnets públicas y privadas, y sus route tables asociadas.
- El Internet Gateway y NAT Gateway existentes.
- Los Security Groups opcionales indicados en `additional_node_security_group_ids`.

Se crean con Terraform:
- El clúster EKS y su configuración de seguridad necesaria.
- El Managed Node Group con dos nodos.
- El Security Group de RDS, que permite PostgreSQL desde el Security Group de los nodos EKS.
- El DB subnet group y la instancia RDS PostgreSQL.

Aunque sea posible consultar Security Groups existentes, no es aconsejable adjuntar automáticamente cualquier SG a EKS o RDS. El módulo EKS crea su SG de nodos con reglas requeridas para el clúster; RDS necesita reglas específicas y restrictivas, por eso este proyecto crea un SG dedicado a la base de datos.

Los data sources solo leen infraestructura; no crean ni reparan rutas, no asocian NAT ni IGW, y no modifican tags de subnets. La red existente debe estar configurada correctamente antes de ejecutar el proyecto.

## Prerrequisitos de red

Antes de ejecutar Terraform, comprueba que:

1. La VPC exista en la región seleccionada.
2. `private_subnet_ids` incluya al menos dos subnets privadas en AZ distintas. Se usan para los nodos EKS y el DB subnet group de RDS.
3. `public_subnet_ids` incluya al menos dos subnets públicas existentes. Se consultan para validar la topología y servirán para futuros balanceadores.
4. El Internet Gateway indicado esté adjunto a esa VPC.
5. El NAT Gateway indicado esté en estado `available`, en una subnet pública de esa VPC, y las route tables de las subnets privadas tengan una ruta de salida correcta hacia NAT.
6. Las subnets privadas tengan salida suficiente para los nodos (NAT Gateway o VPC endpoints requeridos).
7. Las subnets tengan los tags requeridos por EKS y los balanceadores que piensas usar. En particular, verifica `kubernetes.io/cluster/diplomado-k8s` en las subnets para el Node Group; para descubrimiento de balanceadores, suele necesitarse `kubernetes.io/role/elb=1` en subnets públicas y `kubernetes.io/role/internal-elb=1` en subnets privadas.
8. El endpoint público de la API de EKS solo permita la IP pública administrativa indicada con `/32`. No uses `0.0.0.0/0` para el laboratorio.

El código consulta IGW y NAT por ID para confirmar que existen. No cambia ni controla sus rutas.

## 1. Configurar infraestructura EKS y RDS

```bash
cd 01-eks-rds
cp terraform.tfvars.example terraform.tfvars
```

Edita `terraform.tfvars`:
- Reemplaza IDs ficticios con los IDs reales de VPC, subnets, IGW y NAT.
- Sustituye `YOUR_PUBLIC_IP/32` por la IP pública de quien administrará el clúster.
- Usa una contraseña fuerte para `db_password`.
- Si `additional_node_security_group_ids` no es necesario, déjalo como `[]`.

Ejecuta:

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

El plan creará EKS, dos nodos de tipo `t3.medium` por defecto, el Security Group de RDS y RDS PostgreSQL. No crea la VPC, subnets, IGW ni NAT.

**Costos:** EKS, dos instancias EC2, RDS, almacenamiento y transferencia de datos generan costos. Este ejemplo usa una instancia RDS pequeña y no habilita Multi-AZ para contener el costo del taller; no es una configuración de alta disponibilidad para producción. `skip_final_snapshot = true` facilita destruir el laboratorio, pero elimina la base sin snapshot final.

La contraseña de RDS se guarda en el estado Terraform. Mantén los estados fuera de Git y usa un backend con acceso restringido si varias personas administran el proyecto.

## 2. Conectar kubectl a EKS

Ejecuta el comando de output de Terraform o:

```bash
aws eks update-kubeconfig --region us-east-1 --name diplomado-k8s
kubectl get nodes -o wide
kubectl get nodes --show-labels
```

Los nodos deberían mostrar el label `environment=development`. El Node Group se distribuye en las subnets privadas proporcionadas, situadas idealmente en dos AZ distintas.

## 3. Crear el Namespace

```bash
cd ../02-namespace
cp terraform.tfvars.example terraform.tfvars
```

Edita `namespace_name` si deseas otro nombre, y ejecuta:

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Este segundo proyecto usa un estado separado del de EKS.

## 4. Preparar las imágenes y manifiestos

Antes de aplicar los manifiestos:

1. Publica las imágenes reales `saludos-backend:1.0` y `saludos-frontend:1.0` en ECR u otro registry accesible desde los nodos.
2. Reemplaza `REEMPLAZAR_POR_URI_ECR` por las URI reales de las imágenes.
3. Verifica que el Namespace declarado en YAML (por defecto `saludos-dev`) coincida con `namespace_name`.
4. Los Deployments tienen dos réplicas y `topologySpreadConstraints` por `kubernetes.io/hostname`, además de `nodeSelector: environment=development`, para practicar la distribución entre dos nodos.
5. Las variables DB_* del ejemplo deben coincidir con las variables que realmente lee el backend de Saludos. Si la aplicación de clase no utiliza RDS, puedes omitir la configuración de base de datos.

Consulta el endpoint RDS:

```bash
cd ../01-eks-rds
terraform output rds_endpoint
terraform output rds_database_name
```

Copia el endpoint de RDS en `yamls/application/saludos-db-config.yaml`, reemplazando `REEMPLAZAR_POR_OUTPUT_RDS_ENDPOINT`.

Para crear el Secret, copia la plantilla a un nombre de manifiesto local (ignorado por Git):

```bash
cp ../yamls/database-template/saludos-db-secret.example ../yamls/application/saludos-db-secret.yaml
```

Edita `saludos-db-secret.yaml` y reemplaza `DB_PASSWORD` por la misma contraseña configurada para RDS en Terraform. No guardes credenciales reales en Git.

Aplica los manifiestos:

```bash
kubectl apply -f ../yamls/application/
kubectl get pods -n saludos-dev -o wide
kubectl get services -n saludos-dev
```

Los Services son `ClusterIP` (solo internos al clúster). Para probar el frontend desde la máquina administrativa:

```bash
kubectl port-forward service/saludos-frontend 8080:80 -n saludos-dev
```

Abre `http://localhost:8080`.

## RDS: diseño de conectividad

- RDS no es público: `publicly_accessible = false`.
- El DB subnet group utiliza las subnets privadas existentes en al menos dos AZ.
- El SG de RDS permite TCP/5432 desde el Security Group creado por el módulo EKS para los nodos.
- En la configuración por defecto de Amazon VPC CNI, el tráfico de red de los Pods normalmente está asociado a la seguridad de los nodos. Si se habilita Security Groups for Pods u otro modelo de red, revisa las reglas según ese diseño.
- RDS no es un objeto de Kubernetes y no se crea mediante los YAML de la aplicación.

## Limpieza

Primero elimina los recursos Kubernetes y el Namespace (por su estado independiente):

```bash
cd 02-namespace
terraform destroy
```

Después destruye EKS y RDS:

```bash
cd ../01-eks-rds
terraform destroy
```

Esto no destruye la VPC, subnets, route tables, IGW ni NAT consultados mediante `data`. Revisa siempre el plan de destrucción antes de confirmar.
