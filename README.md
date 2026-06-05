# AWS Serverless Integration Pipeline (EDA)

Pipeline de integracion empresarial basado en **Arquitectura Orientada a Eventos (EDA)**
para un e-commerce, ejecutado 100% local con **Podman** y **LocalStack**. Replica patrones
clasicos de middleware (MuleSoft, TIBCO Business Works) usando servicios nativos de AWS.

---

## Arquitectura

```
Postman / curl
     |
     v
API Gateway (REST)                 <- Fase de ingesta HTTP
     |        /orders POST
     v
Lambda proxy (api_handler.py)      <- Reenvia a SQS
     |
     v
SQS                                <- Fase 1: Desacoplamiento (cola)
     |        cola-pedidos-ecommerce
     v
Lambda procesadora                 <- Fase 2: Procesamiento (disparado por SQS)
     |        (index.lambda_handler)
     v
CloudWatch Logs                    <- Logs de ejecucion
```

### Flujo de datos

1. Un pedido llega como HTTP POST a API Gateway `/orders`
2. API Gateway invoca la Lambda proxy mediante integracion `AWS_PROXY`
3. La Lambda proxy encola el pedido en SQS usando boto3
4. SQS retiene el mensaje hasta que un consumidor lo procese
5. La Lambda procesadora se activa **automaticamente** (event source mapping SQS)
6. Lambda extrae los campos del pedido, los transforma y los registra en CloudWatch
7. SQS elimina el mensaje tras una ejecucion exitosa

### Nota sobre LocalStack 4.x

LocalStack 4.x con Docker habilitado lanza **un contenedor Podman por invocacion de
Lambda** (ej. `localstack-pipeline-lambda-procesador-pedidos-lambda-<hash>`). Los logs
de cada ejecucion van a esos contenedores y a CloudWatch Logs, no al contenedor
principal de LocalStack. Los scripts `verify_logs.ps1` y `dump_logs.ps1` los
inspeccionan automaticamente.

---

## Lo que se ha automatizado (este proyecto)

| Antes (manual) | Ahora (automatizado) |
|----------------|----------------------|
| Arrancar LocalStack en una terminal separada | `start_localstack.ps1` — arranca en background + espera a que este listo |
| Crear cola SQS, empaquetar Lambda, desplegar: 3 comandos sueltos | `package_lambda.ps1` + `deploy_lambda.ps1` — creacion o actualizacion idempotente |
| **El trigger SQS-Lambda no existia** — la Lambda nunca se disparaba sola | `create_trigger.ps1` — conecta SQS -> Lambda con `create-event-source-mapping` |
| La Lambda se desplegaba pero quedaba en estado `Pending` y fallaba al invocarse | `deploy_lambda.ps1` ahora espera a que la funcion este `Active` |
| No habia forma de ver los logs de la Lambda | `verify_logs.ps1` — inspecciona contenedores ejecutores + CloudWatch |
| Enviar JSON con espacios al body de SQS rompia el quoting de PowerShell | `publish_message_to_queue.ps1` usa archivo temporal para el body |
| El pipeline completo requeria 5+ comandos en orden exacto | `deploy_all.ps1` — despliegue completo en un solo comando |
| Los contenedores ejecutores se acumulaban entre pruebas | `cleanup_containers.ps1` — los elimina sin reiniciar LocalStack |
| No habia forma de obtener un dump completo de logs | `dump_logs.ps1` — vuelca todo a un archivo con timestamp |
| No existia un punto de entrada HTTP para pruebas con Postman | `create_rest_api.ps1` — crea API Gateway REST con Lambda proxy |
| Limpieza manual de contenedores | `teardown.ps1` — borra recursos y para LocalStack |

---

## Prerrequisitos

- **Windows** con PowerShell 5.1+
- **Podman** instalado (`podman --version`)
- WSL2 con kernel de Linux actualizado (Podman corre sobre WSL)
- Puertos **4566** y **4510-4559** libres

---

## Mapa de scripts

```
scripts/
├── start_localstack.ps1           # Arranca LocalStack en background + health check
├── deploy_all.ps1                 # ORQUESTADOR: ejecuta todo el pipeline secuencialmente
├── teardown.ps1                   # Limpia todos los recursos y para LocalStack
├── cleanup_containers.ps1         # Elimina solo contenedores ejecutores Lambda
├── dump_logs.ps1                  # Vuelca todos los logs a logs/<timestamp>.log
│
├── queues/
│   ├── create_queue.ps1           # Crea cola SQS (idempotente)
│   ├── publish_message_to_queue.ps1  # Envia un pedido de prueba a la cola
│   └── receive_message.ps1        # Lee mensajes de la cola (debug)
│
├── lambda/
│   ├── package_lambda.ps1         # Comprime index.py -> funcion_lambda.zip
│   ├── deploy_lambda.ps1          # Crea o actualiza la funcion Lambda + espera a Active
│   ├── create_trigger.ps1         # Conecta SQS -> Lambda (event source mapping)
│   └── verify_logs.ps1            # Muestra logs de ejecucion (contenedor + ejecutores)
│
└── api/
    └── create_rest_api.ps1        # Crea API Gateway REST + Lambda proxy -> SQS
```

---

## Ejecucion paso a paso

### 1. Despliegue completo (un solo comando)

```powershell
.\scripts\deploy_all.ps1
```

Pasos ejecutados:
0. Limpiar contenedores ejecutores de tandas anteriores
1. Arrancar LocalStack (con `ls-net`, Docker socket, servicios lambda+sqs+logs+apigateway+iam)
2. Crear cola SQS `cola-pedidos-ecommerce`
3. Crear API Gateway REST + Lambda proxy para ingesta HTTP
4. Empaquetar Lambda procesadora (`index.py`)
5. Desplegar Lambda procesadora
6. Crear event source mapping SQS -> Lambda
7. Enviar mensaje de prueba a SQS
8. Verificar logs de ejecucion

### 2. Ejecucion paso a paso (modo aprendizaje)

#### Paso 1: Arrancar LocalStack

```powershell
.\scripts\start_localstack.ps1
```

**Que hace:**
- Lanza LocalStack 4.0.3 en un contenedor Podman en modo detached (`-d`)
- Crea una red Podman personalizada `ls-net` para que los ejecutores Lambda puedan
  comunicarse con LocalStack
- Monta el socket Docker (`/var/run/docker.sock`) para que LocalStack pueda ejecutar
  Lambdas en contenedores aislados
- Expone puertos con `-p` (mapeo bridge)
- Detecta automaticamente la IP de WSL2 y prueba multiples direcciones
  (`127.0.0.1`, `[::1]`, WSL2 IP) para el health check
- Si ya hay un contenedor corriendo, pregunta si quieres reemplazarlo

**Output esperado:**
```
[1/5] Creating Podman network 'ls-net'...
  -> Network ready.
[2/5] Starting LocalStack...
<container-id>
[3/5] Waiting for LocalStack...
  [..] SQS=available Lambda=available (attempt 1)
  [..] SQS=available Lambda=available (attempt 2)
  [OK] LocalStack ready via http://172.28.x.x:4566
[3/5] LocalStack is ready
```

**Que aprendes:** Los servicios cloud no estan disponibles instantaneamente.
En AWS real, aprovisionar una cola SQS o una Lambda lleva segundos. LocalStack
simula este tiempo de arranque. El patron de *health check* con reintentos es el
mismo que usan los orquestadores en produccion (Kubernetes readiness probes,
AWS ECS health checks).

El uso de una red personalizada (`ls-net`) resuelve el problema de comunicacion
entre LocalStack y sus ejecutores Lambda en Podman, que no soporta las IPs
link-local (`169.254.1.2`) que Docker anade al bridge.

---

#### Paso 2: Crear la cola SQS

```powershell
.\scripts\queues\create_queue.ps1
```

**Que hace:**
- Ejecuta `sqs create-queue` contra LocalStack usando la imagen `amazon/aws-cli`
  dentro de Podman
- `--network=host` es **critico**: permite que el contenedor AWS CLI vea LocalStack
  en `127.0.0.1:4566` (sin esto, el contenedor usaria su propia red aislada)

**Output esperado:**
```
[1/2] Creating SQS queue 'cola-pedidos-ecommerce'...
  [OK] Queue created: http://127.0.0.1:4566/000000000000/cola-pedidos-ecommerce
```

**Que aprendes:**
- **SQS (Simple Queue Service)** es un buffer de mensajeria desacoplada. En
  middleware tradicional, esto equivale a un *JMS Queue* (TIBCO EMS, IBM MQ,
  ActiveMQ). En MuleSoft, seria el equivalente a usar el conector Anypoint MQ o JMS.
- El `QueueUrl` contiene `000000000000` — es la cuenta de AWS (12 digitos). En
  LocalStack siempre son ceros; en AWS real seria tu ID de cuenta.
- **Idempotencia**: si ejecutas el comando dos veces, LocalStack devuelve la misma
  URL sin errores.

---

#### Paso 3: Desplegar API Gateway + Lambda proxy

```powershell
.\scripts\api\create_rest_api.ps1
```

**Que hace:**
- Empaqueta y despliega una Lambda proxy (`src/api_handler.py`)
- Crea un API Gateway REST con recurso `/orders` y metodo POST
- Configura integracion `AWS_PROXY` que envia las peticiones HTTP a la Lambda proxy
- La Lambda proxy reenvia el body a SQS usando boto3
- Otorga permisos a API Gateway para invocar la Lambda
- Despliega el API en un stage `dev`

**Output esperado:**
```
[1/7] Packaging proxy Lambda...
  [OK] Package created.
[2/7] Deploying proxy Lambda 'api-gateway-proxy'...
  [OK] Proxy Lambda created.
  -> Waiting for proxy Lambda to become Active...
  [OK] Proxy Lambda active.
[3/7] Granting API Gateway invoke permission...
  [OK] Permission granted.
[4/7] Creating REST API 'ecommerce-orders-api'...
  [OK] API ID: <api-id>
[5/7] Creating resource '/orders'...
  [OK] Resource ID: <resource-id>
[6/7] Configuring POST method with Lambda proxy...
  [OK] Lambda proxy integration configured.
[7/7] Deploying API to stage 'dev'...
  [OK] API deployed.

  Endpoint URL: http://127.0.0.1:4566/restapis/<api-id>/dev/_user_request_/orders
```

**Que aprendes:**
- **API Gateway** es el punto de entrada HTTP para APIs REST. En middleware
  tradicional, equivale a un API Manager o ESB con endpoints HTTP.
- **AWS_PROXY** (integracion tipo proxy) delega todo el request HTTP a una
  Lambda, que es responsable de procesarlo y formatear la respuesta.
- La **Lambda proxy** actua como un adaptor entre el mundo HTTP y el mundo
  asincrono de SQS, similar a un *API Proxy* en MuleSoft o un *HTTP Connector*
  en TIBCO.
- Se usa `AWS_PROXY` en lugar de integracion directa `AWS -> SQS` porque
  LocalStack 4.0.3 tiene un bug en el codigo de integraciones directas con
  servicios (el parche de moto espera objetos pero recibe diccionarios).

---

#### Paso 4: Empaquetar la Lambda procesadora

```powershell
.\scripts\lambda\package_lambda.ps1
```

**Output esperado:**
```
[1/3] Preparing temp folder...
[2/3] Creating ZIP with correct structure...
[3/3] Done: C:\...\src\funcion_lambda.zip
```

**Que aprendes:** AWS Lambda no recibe codigo fuente suelto. Necesita un archivo ZIP
(o imagen de contenedor) con el codigo y sus dependencias. En la nube real, el
limite es 50 MB comprimido. Este empaquetado es analogo a generar un `.jar` en
MuleSoft o un `.ear` en TIBCO para desplegar en el servidor.

---

#### Paso 5: Desplegar la funcion Lambda procesadora

```powershell
.\scripts\lambda\deploy_lambda.ps1
```

**Que hace:**
- Comprueba si la funcion ya existe (`get-function`)
- Si existe: actualiza solo el codigo (`update-function-code`)
- Si no existe: la crea con todos los parametros (`create-function`)
- **Espera a que la funcion pase de `Pending` a `Active`** usando
  `lambda wait function-active-v2`

**Output esperado (primera vez):**
```
[1/3] Checking if Lambda function 'procesador-pedidos-lambda' already exists...
  -> Function does not exist. Creating new function...
[2/3] Deploying Lambda code...
[OK] Lambda function 'procesador-pedidos-lambda' registered.
     ARN: arn:aws:lambda:us-east-1:000000000000:function:procesador-pedidos-lambda
[3/3] Waiting for function to become Active...
  [OK] Function is now Active -- ready to receive events.
```

**Que aprendes:**

Cada parametro del `create-function` tiene un equivalente en middleware tradicional:

| Parametro AWS | Que hace | Equivalente MuleSoft / TIBCO |
|--------------|----------|------------------------------|
| `--function-name` | Nombre del servicio | App name en CloudHub |
| `--runtime python3.12` | Entorno de ejecucion | Version del Mule Runtime |
| `--role arn:aws:iam::...` | Permisos de seguridad | Roles / Policies |
| `--handler index.lambda_handler` | Punto de entrada al codigo | Inbound Flow |
| `--zip-file fileb://...` | Codigo empaquetado | `.jar` de Anypoint Studio |

El **ARN (Amazon Resource Name)** es el DNI universal de cualquier recurso en AWS:
```
arn:particion:servicio:region:cuenta:tipo/recurso
```

La funcion Lambda se crea en estado `Pending` — igual que en AWS real, donde el
servicio necesita tiempo para preparar el entorno de ejecucion.

---

#### Paso 6: Conectar SQS -> Lambda (EL FIX)

```powershell
.\scripts\lambda\create_trigger.ps1
```

**Que hace:**
- Crea un **event source mapping** entre la cola SQS y la funcion Lambda
- Sin esto, la Lambda existe pero nunca se invoca al llegar mensajes a la cola

**Output esperado:**
```
[1/4] Verifying SQS queue 'cola-pedidos-ecommerce' exists...
  [OK] Queue found.
[2/4] Verifying Lambda function 'procesador-pedidos-lambda' exists...
  [OK] Lambda function found.
[3/4] Checking for existing event source mappings...
  -> No existing mapping found.
[4/4] Creating SQS event source mapping (Lambda trigger)...
  -> Function : procesador-pedidos-lambda
  -> Queue ARN: arn:aws:sqs:us-east-1:000000000000:cola-pedidos-ecommerce
  [OK] Event source mapping created! UUID: <uuid>
```

**Que aprendes (concepto clave del proyecto):**
- **Event Source Mapping** es el puente entre SQS (productor) y Lambda (consumidor).
  Sin el mapping, la Lambda es como un worker de MuleSoft desplegado sin un inbound
  endpoint JMS.
- SQS hace **polling** periodico a la Lambda: cada pocos segundos pregunta si hay
  mensajes nuevos y los envia en lotes de hasta 10.
- La Lambda debe devolver exito explicito para que SQS elimine el mensaje.

---

#### Paso 7: Probar con Postman

```
POST http://127.0.0.1:4566/restapis/<api-id>/dev/_user_request_/orders
Content-Type: application/json
Body: {"id_pedido": 2001, "cliente": "postman-test", "total": 45.50}
```

**Output esperado:**
```json
{
    "message": "Pedido recibido y encolado",
    "messageId": "<uuid>",
    "pedido": { "id_pedido": 2001, "cliente": "postman-test", "total": 45.5 }
}
```

O via curl:
```powershell
curl.exe -X POST http://127.0.0.1:4566/restapis/<api-id>/dev/_user_request_/orders ^
  -H "Content-Type: application/json" ^
  -d "{\"id_pedido\":2001,\"cliente\":\"test\",\"total\":45.5}"
```

**Que aprendes:**
- El flujo completo sincrono-asincrono: Postman recibe respuesta 200 inmediata,
  mientras SQS encola el mensaje para procesamiento asincrono por la Lambda.
- La Lambda proxy es un *adaptor* que separa el protocolo HTTP del procesamiento
  de fondo, igual que un *API Proxy* en MuleSoft.

---

#### Paso 8: Verificar la ejecucion de la Lambda

```powershell
.\scripts\lambda\verify_logs.ps1
```

**Output esperado:**
```
[SEARCH] Checking Lambda logs for 'procesador-pedidos-lambda'...

--- LocalStack Container Logs (last 50 lines) ---
  (no Lambda invocation entries in main container logs)

--- Lambda Executor Containers ---
  Container: localstack-pipeline-lambda-<hash>
    START RequestId: <uuid> Version: $LATEST
    Procesando Pedido #1001
    Cliente: lherna06
    Importe total: 89.95 EUR
    Pedido #1001 integrado con exito.
    END RequestId: <uuid>
    REPORT RequestId: <uuid> Duration: xxx ms

--- CloudWatch Logs ---
  START RequestId: <uuid>
  Procesando Pedido #1001
  ...

--- Summary ---
[OK] Queue is empty -- all messages have been consumed.
[OK] 1 Lambda executor container(s) are running.
```

**Que aprendes:**
- Cada invocacion Lambda corre en un contenedor aislado, replicando el sandbox
  de AWS real.
- Ciclo de vida: `START` -> codigo -> `END` + `REPORT` (duracion, memoria).
- CloudWatch Logs captura los `print()` de Python.
- Cuando el handler devuelve 200, SQS elimina el mensaje automaticamente.

---

### 3. Diagnostico avanzado

```powershell
# Limpiar solo contenedores ejecutores (deja LocalStack corriendo)
.\scripts\cleanup_containers.ps1

# Dump completo de logs a logs/localstack_dump_<timestamp>.log
.\scripts\dump_logs.ps1
```

### 4. Limpieza total

```powershell
.\scripts\teardown.ps1
.\scripts\teardown.ps1 -Hard    # Forzado
```

---

## Mapa de conceptos: AWS <-> Middleware tradicional

| Concepto | AWS | MuleSoft / TIBCO |
|----------|-----|------------------|
| Punto de entrada HTTP | API Gateway | API Manager / ESB HTTP endpoint |
| Adaptor HTTP -> cola | Lambda proxy | API Proxy / HTTP Connector |
| Cola de mensajes | SQS | JMS Queue / Anypoint MQ |
| Procesador de fondo | Lambda (procesadora) | Mule Flow / TIBCO BW Process |
| Trigger desacoplado | Event Source Mapping | Inbound Endpoint / JMS Receiver |
| Evento | Mensaje JSON / SQS event | Mule Message / TIBCO JMS Message |
| Permisos | IAM Role | Policy / Client ID |
| Logs | CloudWatch Logs | Mule logs / TIBCO Administrator |
| Entorno local | LocalStack | Anypoint Studio / TIBCO Designer |
| IaC | AWS CLI / CloudFormation | Anypoint Studio deploy |

---

## Troubleshooting

| Sintoma | Causa | Solucion |
|---------|-------|----------|
| LocalStack no arranca | Puerto 4566 ocupado | `netstat -ano \| findstr :4566` y mata el proceso |
| AWS CLI no conecta con LocalStack | Falta `--network=host` | Anade `--network=host` al comando `podman run` |
| Health check no encuentra LocalStack | Solo accesible via WSL2 IP | El script detecta la IP de WSL2 automaticamente |
| Lambda no se invoca al enviar mensaje | Falta event source mapping | Ejecuta `create_trigger.ps1` |
| Lambda se ejecuta pero no hay logs | LocalStack usa contenedores separados | `verify_logs.ps1` ya los inspecciona |
| Lambda da error "Pending" | La funcion no termino de activarse | `deploy_lambda.ps1` espera a `Active` |
| JSON SQS se rompe al enviarlo | PowerShell quoting | `publish_message_to_queue.ps1` usa archivo temporal |
| Contenedor `localstack-pipeline` ya existe | Ejecucion previa | Responde "y" al prompt o usa `-Recreate` |
| Se acumulan ejecutores Lambda | Un contenedor por invocacion | Ejecuta `cleanup_containers.ps1` |
| API Gateway devuelve 404 | Stage no desplegado | Revisar deployments con `get-deployments` |
| API Gateway devuelve 502 | Lambda proxy no existe o falla | Revisar logs de la proxy en CloudWatch |

---

## Resumen de aprendizaje

Al completar este pipeline has practicado:

1. **Event-Driven Architecture (EDA)** — desacoplamiento total entre ingesta HTTP,
   cola de mensajes y procesamiento de fondo
2. **API Gateway** — creacion de REST APIs, recursos, metodos, integraciones
   `AWS_PROXY`, despliegue por stages
3. **AWS Lambda** — dos funciones distintas: proxy (adaptador HTTP->SQS) y
   procesadora (logica de negocio desde SQS)
4. **AWS SQS** — colas, envio, recepcion, ARNs, payload quoting
5. **Event Source Mapping** — puente SQS -> Lambda con polling automatico
6. **LocalStack 4.x** — emulacion local, red personalizada con Podman para
   ejecutores Lambda, health checks
7. **Podman** — contenedores rootless, redes, volumenes, socket Docker,
   resolucion de problemas WSL2/Windows
8. **PowerShell avanzado** — splatting, quoting, archivos temporales,
   orquestacion, manejo de errores de parsing
9. **Patrones de middleware** — equivalentes entre AWS serverless y
   MuleSoft/TIBCO: API Gateway vs API Manager, Lambda proxy vs API Proxy,
   SQS vs JMS, Event Source Mapping vs Inbound Endpoint

---

## Terraform Implementation (Infrastructure as Code)

Ademas del pipeline basado en scripts de PowerShell, el proyecto incluye una
implementacion paralela usando **Terraform** como herramienta de Infrastructure
as Code (IaC). Esta version reemplaza los comandos imperativos de AWS CLI por
recursos declarativos en HCL, gestionando automaticamente el orden de creacion,
dependencias y estado de la infraestructura.

> Los scripts originales en `scripts/` se conservan integros como referencia
> educativa. La implementacion Terraform es autonoma dentro de `terraform/`.

---

### Directorio `terraform/`

```
terraform/
├── versions.tf                 # Versiones de Terraform y providers
├── provider.tf                 # Provider AWS apuntando a LocalStack
├── variables.tf                # Variables de entrada
├── locals.tf                   # Constantes locales (nombres, ARNs, tags)
├── iam.tf                      # Rol y politica de ejecucion para Lambda
├── sqs.tf                      # Cola SQS
├── lambda.tf                   # Funciones Lambda (procesadora + proxy)
├── triggers.tf                 # Event source mapping SQS -> Lambda + permiso API Gateway
├── api_gateway.tf              # API Gateway REST + recurso /orders + metodo POST + integracion
├── outputs.tf                  # Outputs: endpoint URL, ARNs, nombres
├── terraform.tfvars.example    # Ejemplo de archivo de variables
│
├── lib/
│   └── Get-Terraform.ps1       # Helper: localiza terraform.exe portatil
│
├── download_terraform.ps1      # Descarga terraform.exe portatil a tools/
├── start_localstack.ps1        # Arranca LocalStack en Podman
├── stop_localstack.ps1         # Detiene el contenedor de LocalStack
├── apply.ps1                   # Orquestador: init + apply + outputs
├── destroy.ps1                 # Destruye recursos + opcionalmente para LocalStack
├── test_message.ps1            # Envia un pedido de prueba a SQS
└── verify.ps1                  # Verifica logs de la Lambda procesadora
```

---

### Descripcion de los archivos Terraform (.tf)

#### `versions.tf` — Restricciones de version

Define las versiones minimas de Terraform (>= 1.6) y los providers necesarios:
`hashicorp/aws` (~> 5.0) y `hashicorp/archive` (~> 2.0). El provider `archive`
se usa para empaquetar automaticamente el codigo Python de las Lambdas en
archivos ZIP.

#### `provider.tf` — Conexion con LocalStack

Configura el provider AWS para que apunte a LocalStack en lugar de a AWS real:

```hcl
provider "aws" {
  region                      = var.region
  access_key                  = "mock-access-key"
  secret_key                  = "mock-secret-key"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  s3_use_path_style           = true

  endpoints {
    apigateway = var.localstack_endpoint
    cloudwatch = var.localstack_endpoint
    iam        = var.localstack_endpoint
    lambda     = var.localstack_endpoint
    logs       = var.localstack_endpoint
    sqs        = var.localstack_endpoint
  }
}
```

- `skip_*` flags: necesarios porque LocalStack usa credenciales ficticias
  (`mock-access-key` / `mock-secret-key`) y no tiene metadata real de AWS
- `endpoints`: cada servicio AWS se redirige a `http://localhost:4566`
  (o al endpoint configurado en `var.localstack_endpoint`)

**Diferencia clave con los scripts:** En la version PowerShell, cada comando
AWS CLI se ejecuta dentro de un contenedor Podman con `--network=host`. En
Terraform, el provider habla directamente con LocalStack via HTTP desde el
host, sin necesidad de contenedores intermediarios.

#### `variables.tf` — Parametrizacion

```hcl
variable "region"                { default = "us-east-1" }
variable "localstack_endpoint"   { default = "http://localhost:4566" }
variable "lambda_timeout"        { default = 30 }
variable "lambda_memory_size"    { default = 128 }
```

Permite cambiar la region, el endpoint de LocalStack (util si se ejecuta en
WSL2 con una IP diferente), o los recursos de las Lambdas sin modificar el
codigo fuente.

#### `locals.tf` — Constantes del proyecto

Centraliza todos los nombres de recursos y valores derivados:

```hcl
locals {
  queue_name             = "cola-pedidos-ecommerce"
  processor_function_name = "procesador-pedidos-lambda"
  proxy_function_name    = "api-gateway-proxy"
  runtime                = "python3.12"
}
```

En los scripts PowerShell, estos valores estaban repetidos en cada archivo
(`create_queue.ps1`, `deploy_lambda.ps1`, `create_rest_api.ps1`, etc.).
Terraform los centraliza en un solo lugar, eliminando duplicacion.

#### `iam.tf` — Seguridad (Roles y politicas)

Crea un rol de ejecucion para Lambda con una politica que permite:

```hcl
resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action  = "sts:AssumeRole"
    }]
  })
}
```

**Permisos concedidos:**
- `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents` — escritura
  en CloudWatch Logs
- `sqs:ReceiveMessage`, `sqs:DeleteMessage`, `sqs:GetQueueAttributes` — las
  Lambdas necesitan estos permisos para consumir mensajes de SQS
- `sqs:SendMessage` — la Lambda proxy necesita encolar mensajes

En la version PowerShell, el rol se referenciaba con un ARN quemado
(`arn:aws:iam::000000000000:role/lambda-ex`). En Terraform se crea
explícitamente, lo que lo hace portable a AWS real.

#### `sqs.tf` — Cola de mensajes

```hcl
resource "aws_sqs_queue" "orders" {
  name                       = "cola-pedidos-ecommerce"
  visibility_timeout_seconds = 30
  max_message_size           = 262144
  message_retention_seconds  = 345600  # 4 dias
}
```

Convierte 3 lineas de AWS CLI en un recurso declarativo. Terraform gestiona
la idempotencia: si la cola ya existe, no la duplica.

#### `lambda.tf` — Funciones Lambda

Utiliza el data source `archive_file` para empaquetar automaticamente el codigo
Python en ZIP:

```hcl
data "archive_file" "processor" {
  type        = "zip"
  source_file = "${path.module}/../src/index.py"
  output_path = "${path.module}/../src/funcion_lambda.zip"
}

resource "aws_lambda_function" "processor" {
  filename         = data.archive_file.processor.output_path
  function_name    = "procesador-pedidos-lambda"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.processor.output_base64sha256
}
```

**Que hace automaticamente:**
- Comprime `src/index.py` en `funcion_lambda.zip`
- Sube el ZIP a LocalStack como codigo de la funcion
- Si el archivo fuente cambia, detecta el cambio por el hash SHA256 y
  actualiza solo el codigo (sin recrear la funcion)
- Espera a que la funcion pase a estado `Active`

En los scripts PowerShell, este proceso requeria dos scripts separados:
`package_lambda.ps1` (empaquetar) y `deploy_lambda.ps1` (desplegar + esperar).
Terraform lo unifica en un solo recurso.

```hcl
resource "aws_lambda_function" "proxy" {
  # Misma estructura, pero usando src/api_handler.py
  handler = "api_handler.lambda_handler"
}
```

**Nota importante:** No se define la variable de entorno `AWS_ENDPOINT_URL`.
LocalStack 4.x inyecta automaticamente la URL correcta del endpoint en el
contenedor ejecutor de la Lambda. Si se definiera explicitamente como
`http://localhost:4566`, la Lambda proxy fallaria porque dentro del contenedor
ejecutor `localhost` apunta a si mismo, no a LocalStack.

#### `triggers.tf` — Conexiones entre servicios

Dos recursos clave:

```hcl
# Event source mapping: SQS -> Lambda procesadora
resource "aws_lambda_event_source_mapping" "sqs_to_processor" {
  event_source_arn = aws_sqs_queue.orders.arn
  function_name    = aws_lambda_function.processor.arn
  enabled          = true
  batch_size       = 10
}

# Permiso: API Gateway -> Lambda proxy
resource "aws_lambda_permission" "api_gateway_invoke_proxy" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.proxy.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${local.account_id}:${aws_api_gateway_rest_api.ecommerce.id}/*/*/*"
}
```

El **event source mapping** es el equivalente al script `create_trigger.ps1`.
Sin este recurso, la Lambda procesadora existe pero nunca se invoca al llegar
mensajes a la cola.

El **Lambda permission** es el equivalente al comando `lambda add-permission`
en `create_rest_api.ps1`. Sin este permiso, API Gateway no puede invocar la
Lambda proxy.

#### `api_gateway.tf` — API REST

Define los 5 recursos necesarios para exponer el endpoint HTTP:

```hcl
resource "aws_api_gateway_rest_api" "ecommerce" { }           # La API en si
resource "aws_api_gateway_resource" "orders" { }               # El recurso /orders
resource "aws_api_gateway_method" "post_orders" { }            # Metodo POST
resource "aws_api_gateway_integration" "lambda_proxy" { }     # Integracion AWS_PROXY
resource "aws_api_gateway_deployment" "dev" { }                # Despliegue al stage dev
```

El deployment incluye un `triggers` para forzar un nuevo despliegue cuando la
integracion cambia:

```hcl
resource "aws_api_gateway_deployment" "dev" {
  triggers = {
    integration_hash = sha1(jsonencode(aws_api_gateway_integration.lambda_proxy))
  }
}
```

Sin este trigger, Terraform no detectaria que un cambio en la integracion
requiere un nuevo despliegue (un problema conocido de Terraform + API Gateway).

#### `outputs.tf` — Informacion de salida

```hcl
output "api_endpoint" {
  value = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.ecommerce.id}/dev/_user_request_/orders"
}
output "sqs_queue_url"           { value = aws_sqs_queue.orders.url }
output "processor_lambda_arn"    { value = aws_lambda_function.processor.arn }
output "proxy_lambda_arn"        { value = aws_lambda_function.proxy.arn }
```

Equivalentes a los mensajes de exito que los scripts PowerShell mostraban al
final de cada paso.

---

### Scripts PowerShell de soporte (en `terraform/`)

Aunque la infraestructura se define en Terraform, algunos scripts PowerShell
son necesarios para el entorno local:

| Script | Funcion | Equivalente en `scripts/` |
|--------|---------|---------------------------|
| `start_localstack.ps1` | Arranca LocalStack en Podman y espera health check | `scripts/start_localstack.ps1` |
| `stop_localstack.ps1` | Detiene o elimina el contenedor LocalStack | (nuevo, basado en `scripts/teardown.ps1`) |
| `apply.ps1` | Orquestador: verifica LocalStack, `terraform init`, `terraform apply` | `scripts/deploy_all.ps1` |
| `destroy.ps1` | `terraform destroy` + opcionalmente para LocalStack | `scripts/teardown.ps1` |
| `test_message.ps1` | Envia un mensaje JSON de prueba a SQS | `scripts/queues/publish_message_to_queue.ps1` |
| `verify.ps1` | Inspecciona logs de la Lambda en contenedores ejecutores y CloudWatch | `scripts/lambda/verify_logs.ps1` |
| `download_terraform.ps1` | Descarga terraform.exe portatil a `tools/` (sin instalacion global) | (nuevo) |
| `lib/Get-Terraform.ps1` | Helper para localizar terraform.exe: `tools/` -> PATH -> descarga | (nuevo) |

**Diferencia clave:** Los scripts en `scripts/` ejecutan comandos AWS CLI
directamente. Los scripts en `terraform/` ejecutan `terraform apply` /
`terraform destroy`, que a su vez llama al provider AWS.

---

### Flujo de ejecucion Terraform

```
Postman / curl
     |
     v
API Gateway (REST)                   <- Creado por: aws_api_gateway_*
     |        /orders POST
     v
Lambda proxy (api_handler.py)        <- Creado por: aws_lambda_function.proxy
     |                                    Permiso:  aws_lambda_permission
     v
SQS "cola-pedidos-ecommerce"         <- Creado por: aws_sqs_queue.orders
     |
     v
Lambda procesadora                   <- Creado por: aws_lambda_function.processor
     | (index.lambda_handler)            Trigger:   aws_lambda_event_source_mapping
     v
CloudWatch Logs                      <- Logs gestionados por el rol IAM
```

**Orden de creacion (gestionado automaticamente por Terraform):**

1. `aws_iam_role.lambda_exec` — el rol debe existir antes que las Lambdas
2. `aws_sqs_queue.orders` — la cola debe existir antes que el trigger
3. `aws_lambda_function.proxy` + `aws_lambda_function.processor` — las
   Lambdas necesitan el rol IAM
4. `aws_lambda_event_source_mapping` — necesita la cola y la Lambda
5. `aws_api_gateway_*` — necesita la Lambda proxy
6. `aws_lambda_permission` — necesita la Lambda proxy y la API Gateway

En los scripts PowerShell, este orden se controlaba manualmente en
`deploy_all.ps1`. Terraform lo resuelve automaticamente analizando las
referencias entre recursos.

---

### Comparativa: Scripts vs Terraform

| Aspecto | Scripts PowerShell (`scripts/`) | Terraform (`terraform/`) |
|---------|--------------------------------|--------------------------|
| **Paradigma** | Imperativo (paso a paso) | Declarativo (estado deseado) |
| **Idempotencia** | Implementada manualmente con `if exists...` | Automatica (Terraform compara estado) |
| **Orden de creacion** | Orquestado en `deploy_all.ps1` | Grafo de dependencias automatico |
| **AWS CLI** | Ejecutado dentro de contenedor Podman | Provider AWS via HTTP directo a LocalStack |
| **Empaquetado Lambda** | Script separado `package_lambda.ps1` | `archive_file` data source automatico |
| **Deteccion de cambios** | Manual (no detecta cambios en codigo) | Automatica via `source_code_hash` |
| **Destruccion** | `teardown.ps1` (scripts ad-hoc) | `terraform destroy` |
| **Estado** | No gestionado (comandos sueltos) | `terraform.tfstate` (rastrea todo) |
| **Portabilidad** | Windows + Podman solamente | Cualquier SO + cualquier ejecutor |
| **Produccion** | No (disenado solo para LocalStack) | Si (mismos recursos funcionan en AWS real) |

---

### Flujo de trabajo completo (Terraform)

```powershell
# 0. Una sola vez: descargar Terraform portatil
cd terraform
.\download_terraform.ps1

# 1. Arrancar LocalStack
.\start_localstack.ps1 -Force

# 2. Desplegar toda la infraestructura
.\apply.ps1 -AutoApprove

# 3. Probar con Postman o mediante script
.\test_message.ps1

# 4. Verificar logs de la Lambda procesadora
.\verify.ps1

# 5. Destruir todo al terminar
.\destroy.ps1 -AutoApprove -AlsoStopLocalStack
```

Sin necesidad de instalar Terraform globalmente: `download_terraform.ps1`
descarga el binario portatil a `terraform/tools/terraform.exe`, y los scripts
`apply.ps1` / `destroy.ps1` lo localizan automaticamente mediante
`lib/Get-Terraform.ps1`.

---

### Mapa de conceptos: Scripts -> Terraform

| Recurso | Script PowerShell | Recurso Terraform |
|---------|-------------------|-------------------|
| Cola SQS | `scripts/queues/create_queue.ps1` | `aws_sqs_queue.orders` |
| Lambda procesadora | `package_lambda.ps1` + `deploy_lambda.ps1` | `aws_lambda_function.processor` + `data.archive_file.processor` |
| Lambda proxy | (dentro de `create_rest_api.ps1`) | `aws_lambda_function.proxy` + `data.archive_file.proxy` |
| Trigger SQS -> Lambda | `scripts/lambda/create_trigger.ps1` | `aws_lambda_event_source_mapping.sqs_to_processor` |
| API Gateway | `scripts/api/create_rest_api.ps1` | `aws_api_gateway_rest_api` + resource + method + integration + deployment |
| Permiso API Gateway | (dentro de `create_rest_api.ps1`) | `aws_lambda_permission.api_gateway_invoke_proxy` |
| Rol IAM | Quemado como ARN fijo | `aws_iam_role.lambda_exec` + `aws_iam_role_policy.lambda_exec` |
| Esperar estado Active | `lambda wait function-active-v2` | Gestionado implicitamente por Terraform |
| Variables repetidas | En cada script individual | Centralizadas en `locals.tf` y `variables.tf` |

---

### Lo que se aprendio con la implementacion Terraform

1. **Provider AWS con LocalStack** — configuracion de endpoints personalizados,
   omision de validacion de credenciales, y diferencias entre LocalStack 3.x y 4.x
2. **`archive_file` data source** — empaquetado automatico de Lambdas sin scripts
   externos, deteccion de cambios via SHA256
3. **API Gateway + Terraform** — manejo del trigger de deployment forzado para
   detectar cambios en la integracion Lambda
4. **Event Source Mapping** — recurso especifico de Terraform que conecta SQS
   con Lambda, equivalente al `create-event-source-mapping` de AWS CLI
5. **Manejo de errores en PowerShell** — diferencia entre `$LASTEXITCODE` y `$?`
   para comandos externos, especialmente cuando el ejecutable no existe
6. **Lambda executor networking** — comprension de que `localhost:4566` dentro
   del contenedor ejecutor de LocalStack no apunta a LocalStack, y que el
   entorno inyectado por LocalStack (`AWS_ENDPOINT_URL`) gestiona esto
   automaticamente si no se sobrescribe
7. **Portabilidad vs educacion** — la version PowerShell es mas educativa
   (cada comando se ve explícitamente), mientras que Terraform es mas apto
   para produccion (declarativo, stateful, portable)
