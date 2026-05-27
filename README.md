# AWS Serverless Integration Pipeline (EDA)

Pipeline de integracion empresarial basado en **Arquitectura Orientada a Eventos (EDA)** para un e-commerce, ejecutado 100% local con **Podman** y **LocalStack**. Replica patrones clasicos de middleware (MuleSoft, TIBCO Business Works) usando servicios nativos de AWS.

---

## Arquitectura

```
Cliente HTTP (futuro)
     |
     v
API Gateway (futuro)              <- Fase de ingesta
     |
     v
SQS --------------------------    <- Fase 1: Desacoplamiento (cola)
     |        cola-pedidos-ecommerce
     |
     v
Lambda (index.lambda_handler)     <- Fase 2: Procesamiento (disparado por SQS)
     |
     v
DynamoDB (futuro)                 <- Fase 3: Persistencia
```

### Flujo de datos

1. Un pedido llega como mensaje JSON a la cola SQS
2. SQS retiene el mensaje hasta que un consumidor lo procese
3. Lambda se activa **automaticamente** (gracias al event source mapping)
4. Lambda extrae los campos del pedido, los transforma y los registra
5. SQS elimina el mensaje automaticamente tras una ejecucion exitosa

### Nota sobre LocalStack 3.x

LocalStack 3.x con Docker habilitado lanza **un contenedor Podman por invocacion de Lambda** (ej. `localstack-pipeline-lambda-procesador-pedidos-lambda-<hash>`). Los logs de cada ejecucion van a esos contenedores, no al contenedor principal de LocalStack. El script `verify_logs.ps1` los inspecciona automaticamente.

---

## Lo que se ha automatizado (este proyecto)

| Antes (manual) | Ahora (automatizado) |
|----------------|----------------------|
| Arrancar LocalStack en una terminal separada | `start_localstack.ps1` — arranca en background + espera a que este listo |
| Crear cola SQS, empaquetar Lambda, desplegar: 3 comandos sueltos | `package_lambda.ps1` + `deploy_lambda.ps1` — creacion o actualizacion idempotente |
| **El trigger SQS-Lambda no existia** — la Lambda nunca se disparaba sola | `create_trigger.ps1` — conecta SQS -> Lambda con `create-event-source-mapping` |
| La Lambda se desplegaba pero quedaba en estado `Pending` y fallaba al invocarse | `deploy_lambda.ps1` ahora espera a que la funcion este `Active` (`lambda wait function-active-v2`) |
| No habia forma de ver los logs de la Lambda (iban a contenedores ejecutores) | `verify_logs.ps1` — inspecciona contenedores ejecutores + contenedor principal + CloudWatch |
| Enviar JSON con espacios al body de SQS rompia el quoting de PowerShell | `publish_message_to_queue.ps1` usa archivo temporal para el body |
| Cada vez habia que ejecutar 5+ comandos en orden exacto | `deploy_all.ps1` — despliegue completo en un solo comando |
| Los contenedores ejecutores se acumulaban entre pruebas | `cleanup_containers.ps1` — los elimina sin reiniciar LocalStack |
| No habia forma de obtener un dump completo de logs para debug | `dump_logs.ps1` — vuelca todo a un archivo con timestamp |
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
└── lambda/
    ├── package_lambda.ps1         # Comprime index.py -> funcion_lambda.zip
    ├── deploy_lambda.ps1          # Crea o actualiza la funcion Lambda + espera a Active
    ├── create_trigger.ps1         # Conecta SQS -> Lambda (event source mapping)
    └── verify_logs.ps1            # Muestra logs de ejecucion (contenedor + ejecutores)
```

---

## Ejecucion paso a paso

### 1. Despliegue completo (un solo comando)

```powershell
.\scripts\deploy_all.ps1
```

Esto ejecuta en orden: LocalStack -> SQS -> empaquetar Lambda -> desplegar Lambda -> esperar Active -> trigger SQS -> mensaje de prueba -> verificacion.

### 2. Ejecucion paso a paso (modo aprendizaje)

#### Paso 1: Arrancar LocalStack

```powershell
.\scripts\start_localstack.ps1
```

**Que hace:**
- Lanza LocalStack 3.0 en un contenedor Podman en modo detached (`-d`)
- Monta el socket Docker (`/var/run/docker.sock`) para que LocalStack pueda ejecutar Lambdas en contenedores aislados
- Expone puertos con `-p` (mapeo bridge) — sin `--network=host` para evitar problemas con el nuevo proveedor Lambda de LocalStack 3.x
- Detecta automaticamente la IP de WSL2 y prueba multiples direcciones (`127.0.0.1`, `[::1]`, WSL2 IP) para el health check
- Si ya hay un contenedor corriendo, pregunta si quieres reemplazarlo

**Output esperado:**
```
[1/5] Starting LocalStack container 'localstack-pipeline'...
[2/5] Waiting for LocalStack services to become available...
  [..] SQS=False Lambda=False (attempt 1)
  [..] SQS=False Lambda=False (attempt 2)
  [OK] All services available (SQS, Lambda)
[3/5] LocalStack is ready at http://127.0.0.1:4566
```

**Que aprendes:** Los servicios cloud no estan disponibles instantaneamente. En AWS real, aprovisionar una cola SQS o una Lambda lleva segundos. LocalStack simula este tiempo de arranque. El patron de *health check* con reintentos es el mismo que usan los orquestadores en produccion (Kubernetes readiness probes, AWS ECS health checks).

---

#### Paso 2: Crear la cola SQS

```powershell
.\scripts\queues\create_queue.ps1
```

**Que hace:**
- Ejecuta `sqs create-queue` contra LocalStack usando la imagen `amazon/aws-cli` dentro de Podman
- `--network=host` es **critico**: permite que el contenedor AWS CLI vea LocalStack en `127.0.0.1:4566` (sin esto, el contenedor usaria su propia red aislada)

**Output esperado:**
```
[1/2] Creating SQS queue 'cola-pedidos-ecommerce'...
  [OK] Queue created: http://127.0.0.1:4566/000000000000/cola-pedidos-ecommerce
```

**Que aprendes:**
- **SQS (Simple Queue Service)** es un buffer de mensajeria desacoplada. En middleware tradicional, esto equivale a un *JMS Queue* (TIBCO EMS, IBM MQ, ActiveMQ). En MuleSoft, seria el equivalente a usar el conector Anypoint MQ o JMS.
- El `QueueUrl` contiene `000000000000` — es la cuenta de AWS (12 digitos). En LocalStack siempre son ceros; en AWS real seria tu ID de cuenta.
- **Idempotencia**: si ejecutas el comando dos veces, LocalStack devuelve la misma URL sin errores.

---

#### Paso 3: Empaquetar la Lambda

```powershell
.\scripts\lambda\package_lambda.ps1
```

**Output esperado:**
```
[1/3] Packaging Lambda code...
  [OK] Lambda package created: C:\...\src\funcion_lambda.zip
```

**Que aprendes:** AWS Lambda no recibe codigo fuente suelto. Necesita un archivo ZIP (o imagen de contenedor) con el codigo y sus dependencias. En la nube real, el limite es 50 MB comprimido. Este empaquetado es analogo a generar un `.jar` en MuleSoft o un `.ear` en TIBCO para desplegar en el servidor.

---

#### Paso 4: Desplegar la funcion Lambda

```powershell
.\scripts\lambda\deploy_lambda.ps1
```

**Que hace:**
- Comprueba si la funcion ya existe (`get-function`)
- Si existe: actualiza solo el codigo (`update-function-code`)
- Si no existe: la crea con todos los parametros (`create-function`)
- **Despues de crear/actualizar, espera a que la funcion pase de `Pending` a `Active`** usando `lambda wait function-active-v2`. Esto evita que las invocaciones fallen porque la funcion no esta lista.

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
| `--runtime python3.12` | Entorno de ejecucion | Version del Mule Runtime (4.4 vs 4.6) |
| `--role arn:aws:iam::...` | Permisos de seguridad | Roles / Policies en AnyPoint Platform |
| `--handler index.lambda_handler` | Punto de entrada al codigo | Inbound Flow / Endpoint receptor |
| `--zip-file fileb://...` | Codigo empaquetado | Artefacto `.jar` generado por Anypoint Studio |

El **ARN (Amazon Resource Name)** es el DNI universal de cualquier recurso en AWS. El formato es:
```
arn:particion:servicio:region:cuenta:tipo/recurso
```

La funcion Lambda se crea en estado `Pending` — igual que en AWS real, donde el servicio necesita tiempo para preparar el entorno de ejecucion. El comando `lambda wait function-active-v2` hace polling hasta que la funcion esta lista.

---

#### Paso 5: Conectar SQS -> Lambda (EL FIX)

```powershell
.\scripts\lambda\create_trigger.ps1
```

**Que hace:**
- Crea un **event source mapping** entre la cola SQS y la funcion Lambda
- Esto es lo que **faltaba** en la configuracion anterior — sin esto, la Lambda existe pero nunca se invoca

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
  [LINK] Lambda will now automatically process messages from 'cola-pedidos-ecommerce'.
```

**Que aprendes (esto es el concepto clave del proyecto):**

- **Event Source Mapping** es el puente entre un servicio productor (SQS) y un consumidor (Lambda). En AWS real, esto se configura automaticamente desde la consola, pero debajo sigue siendo una llamada a `create-event-source-mapping`.
- Sin este mapping, la Lambda **no se entera** de que hay mensajes en la cola. Es como tener un worker de MuleSoft desplegado pero sin un inbound endpoint JMS configurado.
- SQS hace **polling** periodico a la Lambda: cada cierto tiempo (segundos) pregunta "hay mensajes nuevos?". Cuando los hay, invoca la Lambda con un lote de hasta 10 mensajes.
- La Lambda debe devolver un mensaje de exito (o fallo) explicito para que SQS sepa si debe eliminar o reintentar el mensaje.

**El flujo ahora es:**
```
Mensaje JSON -> SQS -> (polling) -> Lambda -> logs
```

---

#### Paso 6: Enviar un mensaje de prueba

```powershell
.\scripts\queues\publish_message_to_queue.ps1
```

**Que hace:**
- Escribe el JSON del body en un archivo temporal y lo monta en el contenedor AWS CLI, evitando problemas de quoting de PowerShell con JSON que contiene espacios y caracteres especiales.
- Usa `--message-body file:///payload/message.json` para leer el contenido desde el archivo montado.

**Output esperado:**
```
[1/2] Publishing test message to queue...
  -> Queue URL: http://127.0.0.1:4566/000000000000/cola-pedidos-ecommerce
  -> Body: {"id_pedido": 1001, "cliente": "lherna06", "total": 89.95, ...}
[OK] Message sent! MessageId: <uuid>
```

**Que aprendes:**
- El mensaje es un **evento** JSON. En EDA, los eventos son inmutables, autocontenidos y representan algo que ya ocurrio ("el pedido 1001 se ha creado").
- SQS garantiza *at-least-once delivery*: un mensaje se entrega al menos una vez, pero podria entregarse multiples veces. El codigo Lambda deberia ser **idempotente**.
- El `MessageId` es un identificador unico que AWS asigna — sirve para tracking y debugging.
- **Leccion tecnica**: pasar JSON por linea de comandos es propenso a errores de quoting. La estrategia de archivo temporal es mas robusta y escalable.

---

#### Paso 7: Verificar la ejecucion de la Lambda

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
  (CloudWatch log group not found)

--- Summary ---
[OK] Queue is empty -- all messages have been consumed.
[OK] 1 Lambda executor container(s) are running -- function is being invoked.
```

**Que aprendes:**
- LocalStack 3.x con Docker habilitado ejecuta cada invocacion Lambda en un contenedor aislado. Esto replica el modelo de ejecucion de AWS real, donde cada invocacion corre en un sandbox separado.
- El ciclo de vida de una invocacion Lambda: `START` -> ejecucion del codigo -> `END` + `REPORT`.
- El `REPORT` incluye metricas de observabilidad: duracion, memoria usada. En AWS real, estos datos van a CloudWatch Logs y CloudWatch Metrics.
- Cuando el handler devuelve `{'statusCode': 200}`, SQS interpreta que el mensaje se proceso correctamente y lo **elimina de la cola** automaticamente.

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
```

O para una limpieza forzada (si algo fallo):

```powershell
.\scripts\teardown.ps1 -Hard
```

---

## Mapa de conceptos: AWS <-> Middleware tradicional

| Concepto | AWS | MuleSoft / TIBCO |
|----------|-----|------------------|
| Cola de mensajes | SQS | JMS Queue / Anypoint MQ |
| Procesador | Lambda | Mule Flow / TIBCO BW Process |
| Trigger / enlace | Event Source Mapping | Inbound Endpoint / JMS Receiver |
| Evento | Mensaje JSON / SQS event | Mule Message / TIBCO JMS Message |
| Permisos | IAM Role | Policy / Client ID |
| Logs | CloudWatch Logs | Mule logs / TIBCO Administrator |
| Entorno local | LocalStack | Anypoint Studio / TIBCO Designer |
| Infraestructura como codigo | AWS CLI / CloudFormation | Anypoint Studio deploy |

---

## Troubleshooting

| Sintoma | Causa | Solucion |
|---------|-------|----------|
| LocalStack no arranca | Puerto 4566 ocupado | `netstat -ano \| findstr :4566` y mata el proceso |
| AWS CLI no conecta con LocalStack | Falta `--network=host` | Anade `--network=host` al comando `podman run` |
| Health check no encuentra LocalStack | Solo accesible via IPv6 o WSL2 IP | Los scripts actuales detectan automaticamente la IP de WSL2 |
| Lambda no se invoca al enviar mensaje | Falta event source mapping | Ejecuta `create_trigger.ps1` |
| Lambda se invoca pero no hay logs en contenedor principal | LocalStack 3.x usa contenedores ejecutores separados | `verify_logs.ps1` ya inspecciona los contenedores ejecutores |
| Lambda da error "Pending" al invocarse | La funcion no ha terminado de activarse | Vuelve a ejecutar `deploy_lambda.ps1` que espera a `Active` |
| El JSON del mensaje SQS se rompe al enviarlo | PowerShell no escapa correctamente las comillas | `publish_message_to_queue.ps1` usa archivo temporal para evitar el problema |
| Contenedor localstack-pipeline ya existe | Ejecucion previa sin teardown | Usa `start_localstack.ps1 -Recreate` o responde "y" al prompt |
| Se acumulan contenedores `localstack-pipeline-lambda-*` | LocalStack lanza un contenedor por invocacion | Ejecuta `cleanup_containers.ps1` entre tandas de pruebas |

---

## Resumen de aprendizaje

Al completar este pipeline has practicado:

1. **Event-Driven Architecture (EDA)** — desacoplamiento total entre productor y consumidor mediante una cola
2. **AWS SQS** — creacion de colas, envio/recepcion de mensajes, URLs vs ARNs, payload quoting
3. **AWS Lambda** — empaquetado, despliegue, handler events, ciclo de vida (Pending -> Active), contenedores ejecutores
4. **Event Source Mapping** — como conectar un servicio productor con un consumidor serverless
5. **LocalStack** — emulacion local de servicios AWS, health checks, Docker-in-Docker para Lambda, idempotencia
6. **Podman** — contenedores rootless, network modes, volumenes bind mount, socket Docker, gestion de contenedores ejecutores
7. **Automatizacion PowerShell** — scripts idempotentes, orquestacion, verificacion post-ejecucion, manejo de errores de quoting
8. **Patron de middleware** — equivalentes entre AWS serverless y MuleSoft/TIBCO
9. **Diagnostico** — inspeccion de logs en contenedores ejecutores, dump completo de logs con timestamp
