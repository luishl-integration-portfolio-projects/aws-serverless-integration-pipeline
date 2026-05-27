# AWS Serverless Integration Pipeline (EDA)

Pipeline de integración empresarial basado en **Arquitectura Orientada a Eventos (EDA)** para un e-commerce, ejecutado 100% local con **Podman** y **LocalStack**. Replica patrones clásicos de middleware (MuleSoft, TIBCO Business Works) usando servicios nativos de AWS.

---

## Arquitectura

```
Cliente HTTP (futuro)
     │
     ▼
API Gateway (futuro)              ← Fase de ingesta
     │
     ▼
SQS ──────────────────────────    ← Fase 1: Desacoplamiento (cola)
     │        cola-pedidos-ecommerce
     │
     ▼
Lambda (index.lambda_handler)     ← Fase 2: Procesamiento (disparado por SQS)
     │
     ▼
DynamoDB (futuro)                 ← Fase 3: Persistencia
```

### Flujo de datos

1. Un pedido llega como mensaje JSON a la cola SQS
2. SQS retiene el mensaje hasta que un consumidor lo procese
3. Lambda se activa **automáticamente** (gracias al event source mapping)
4. Lambda extrae los campos del pedido, los transforma y los registra
5. SQS elimina el mensaje automáticamente tras una ejecución exitosa

---

## Lo que se ha automatizado (este proyecto)

| Antes (manual) | Ahora (automatizado) |
|----------------|----------------------|
| Arrancar LocalStack en una terminal separada | `start_localstack.ps1` — arranca en background + espera a que esté listo |
| Crear cola SQS, empaquetar Lambda, desplegar: 3 comandos sueltos | `package_lambda.ps1` + `deploy_lambda.ps1` — creación o actualización idempotente |
| **El trigger SQS-Lambda no existía** — la Lambda nunca se disparaba sola | `create_trigger.ps1` — conecta SQS → Lambda con `create-event-source-mapping` |
| No había forma de ver los logs de la Lambda | `verify_logs.ps1` — inspecciona los logs del contenedor y CloudWatch |
| Cada vez había que ejecutar 5+ comandos en orden exacto | `deploy_all.ps1` — despliegue completo en un solo comando |
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
│
├── queues/
│   ├── create_queue.ps1           # Crea cola SQS (idempotente)
│   ├── publish_message_to_queue.ps1  # Envía un pedido de prueba a la cola
│   └── receive_message.ps1        # Lee mensajes de la cola (debug)
│
└── lambda/
    ├── package_lambda.ps1         # Comprime index.py → funcion_lambda.zip
    ├── deploy_lambda.ps1          # Crea o actualiza la función Lambda
    ├── create_trigger.ps1         # Conecta SQS → Lambda (event source mapping)
    └── verify_logs.ps1            # Muestra los logs de ejecución de la Lambda
```

---

## Ejecución paso a paso

### 1. Despliegue completo (un solo comando)

```powershell
.\scripts\deploy_all.ps1
```

Esto ejecuta en orden: LocalStack → SQS → empaquetar Lambda → desplegar Lambda → trigger SQS → mensaje de prueba → verificación.

### 2. Ejecución paso a paso (modo aprendizaje)

#### Paso 1: Arrancar LocalStack

```powershell
.\scripts\start_localstack.ps1
```

**Qué hace:**
- Lanza LocalStack 3.0 en un contenedor Podman en modo detached (`-d`)
- Espera hasta que los servicios SQS y Lambda estén disponibles (polling al endpoint `/health`)
- Usa `--network=host` no es necesario aquí porque exponemos puertos con `-p`

**Output esperado:**
```
[1/5] Starting LocalStack container 'localstack-pipeline'...
[2/5] Waiting for LocalStack services to become available...
  [..] SQS=False Lambda=False (attempt 1)
  [..] SQS=False Lambda=False (attempt 2)
  [OK] All services available (SQS, Lambda)
[3/5] LocalStack is ready at http://127.0.0.1:4566
```

**Qué aprendes:** Los servicios cloud no están disponibles instantáneamente. En AWS real, aprovisionar una cola SQS o una Lambda lleva segundos. LocalStack simula este tiempo de arranque. El patrón de *health check* con reintentos es el mismo que usan los orquestadores en producción (Kubernetes readiness probes, AWS ECS health checks).

---

#### Paso 2: Crear la cola SQS

```powershell
.\scripts\queues\create_queue.ps1
```

**Qué hace:**
- Ejecuta `sqs create-queue` contra LocalStack usando la imagen `amazon/aws-cli` dentro de Podman
- `--network=host` es **crítico**: permite que el contenedor AWS CLI vea LocalStack en `127.0.0.1:4566` (sin esto, el contenedor usaría su propia red aislada)

**Output esperado:**
```
[1/2] Creating SQS queue 'cola-pedidos-ecommerce'...
  [OK] Queue created: http://127.0.0.1:4566/000000000000/cola-pedidos-ecommerce
```

**Qué aprendes:**
- **SQS (Simple Queue Service)** es un buffer de mensajería desacoplada. En middleware tradicional, esto equivale a un *JMS Queue* (TIBCO EMS, IBM MQ, ActiveMQ). En MuleSoft, sería el equivalente a usar el conector Anypoint MQ o JMS.
- El `QueueUrl` contiene `000000000000` — es la cuenta de AWS (12 dígitos). En LocalStack siempre son ceros; en AWS real sería tu ID de cuenta.
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

**Qué aprendes:** AWS Lambda no recibe código fuente suelto. Necesita un archivo ZIP (o imagen de contenedor) con el código y sus dependencias. En la nube real, el límite es 50 MB comprimido. Este empaquetado es análogo a generar un `.jar` en MuleSoft o un `.ear` en TIBCO para desplegar en el servidor.

---

#### Paso 4: Desplegar la función Lambda

```powershell
.\scripts\lambda\deploy_lambda.ps1
```

**Qué hace:**
- Comprueba si la función ya existe (`get-function`)
- Si existe: actualiza solo el código (`update-function-code`)
- Si no existe: la crea con todos los parámetros (`create-function`)

**Output esperado (primera vez):**
```
[1/3] Checking if Lambda function 'procesador-pedidos-lambda' already exists...
  → Function does not exist. Creating new function...
[2/3] Deploying Lambda code...
  [OK] Lambda function 'procesador-pedidos-lambda' deployed.
     ARN: arn:aws:lambda:us-east-1:000000000000:function:procesador-pedidos-lambda
```

**Qué aprendes:**

Cada parámetro del `create-function` tiene un equivalente en middleware tradicional:

| Parámetro AWS | Qué hace | Equivalente MuleSoft / TIBCO |
|--------------|----------|------------------------------|
| `--function-name` | Nombre del servicio | App name en CloudHub |
| `--runtime python3.12` | Entorno de ejecución | Versión del Mule Runtime (4.4 vs 4.6) |
| `--role arn:aws:iam::...` | Permisos de seguridad | Roles / Policies en AnyPoint Platform |
| `--handler index.lambda_handler` | Punto de entrada al código | Inbound Flow / Endpoint receptor |
| `--zip-file fileb://...` | Código empaquetado | Artefacto `.jar` generado por Anypoint Studio |

El **ARN (Amazon Resource Name)** es el DNI universal de cualquier recurso en AWS. El formato es:
```
arn:partición:servicio:región:cuenta:tipo/recurso
```

---

#### Paso 5: Conectar SQS → Lambda (EL FIX)

```powershell
.\scripts\lambda\create_trigger.ps1
```

**Qué hace:**
- Crea un **event source mapping** entre la cola SQS y la función Lambda
- Esto es lo que **faltaba** en la configuración anterior — sin esto, la Lambda existe pero nunca se invoca

**Output esperado:**
```
[1/4] Verifying SQS queue 'cola-pedidos-ecommerce' exists...
  [OK] Queue found.

[2/4] Verifying Lambda function 'procesador-pedidos-lambda' exists...
  [OK] Lambda function found.
[3/4] Checking for existing event source mappings...
  → No existing mapping found.
[4/4] Creating SQS event source mapping (Lambda trigger)...
  → Function : procesador-pedidos-lambda
  → Queue ARN: arn:aws:sqs:us-east-1:000000000000:cola-pedidos-ecommerce
  [OK] Event source mapping created! UUID: <uuid>
  [LINK] Lambda will now automatically process messages from 'cola-pedidos-ecommerce'.
```

**Qué aprendes (esto es el concepto clave del proyecto):**

- **Event Source Mapping** es el puente entre un servicio productor (SQS) y un consumidor (Lambda). En AWS real, esto se configura automáticamente desde la consola, pero debajo sigue siendo una llamada a `create-event-source-mapping`.
- Sin este mapping, la Lambda **no se entera** de que hay mensajes en la cola. Es como tener un worker de MuleSoft desplegado pero sin un inbound endpoint JMS configurado.
- SQS hace **polling** periódico a la Lambda: cada cierto tiempo (segundos) pregunta "¿hay mensajes nuevos?". Cuando los hay, invoca la Lambda con un lote de hasta 10 mensajes.
- La Lambda debe devolver un mensaje de éxito (o fallo) explícito para que SQS sepa si debe eliminar o reintentar el mensaje.

**El flujo ahora es:**
```
Mensaje JSON → SQS → (polling) → Lambda → logs
```

---

#### Paso 6: Enviar un mensaje de prueba

```powershell
.\scripts\queues\publish_message_to_queue.ps1
```

**Output esperado:**
```
[1/2] Publishing test message to queue...
  → Queue URL: http://127.0.0.1:4566/000000000000/cola-pedidos-ecommerce
  → Body: {"id_pedido": 1001, "cliente": "lherna06", "total": 89.95, ...}
  [OK] Message sent! MessageId: <uuid>
  🔄 Lambda should process it within seconds.
```

**Qué aprendes:**
- El mensaje es un **evento** JSON. En EDA, los eventos son inmutables, autocontenidos y representan algo que ya ocurrió ("el pedido 1001 se ha creado").
- SQS garantiza *at-least-once delivery*: un mensaje se entrega al menos una vez, pero podría entregarse múltiples veces. El código Lambda debería ser **idempotente**.
- El `MessageId` es un identificador único que AWS asigna — sirve para tracking y debugging.

---

#### Paso 7: Verificar la ejecución de la Lambda

```powershell
.\scripts\lambda\verify_logs.ps1
```

**Output esperado:**
```
[SEARCH] Checking Lambda logs for 'procesador-pedidos-lambda'...

--- LocalStack Container Logs (last 50 lines) ---
  START RequestId: <uuid> Version: $LATEST
  [BOX] Procesando Pedido #1001
  [USER] Cliente: lherna06
  [MONEY] Importe total: 89.95€
  [OK] Pedido #1001 integrado con éxito.
  END RequestId: <uuid>
  REPORT RequestId: <uuid> Duration: xxx ms

--- CloudWatch Logs ---
  (CloudWatch log group not found. Lambda may not have been invoked yet)

--- Summary ---
  [OK] Queue is empty — all messages have been processed.
```

**Qué aprendes:**
- El ciclo de vida de una invocación Lambda: `START` → ejecución del código → `END` + `REPORT`.
- El `REPORT` incluye métricas de observabilidad: duración, memoria usada. En AWS real, estos datos van a CloudWatch Logs y CloudWatch Metrics.
- Cuando el handler devuelve `{'statusCode': 200}`, SQS interpreta que el mensaje se procesó correctamente y lo **elimina de la cola** automáticamente.

---

### 3. Limpieza

```powershell
.\scripts\teardown.ps1
```

O para una limpieza forzada (si algo falló):

```powershell
.\scripts\teardown.ps1 -Hard
```

---

## Mapa de conceptos: AWS ↔ Middleware tradicional

| Concepto | AWS | MuleSoft / TIBCO |
|----------|-----|------------------|
| Cola de mensajes | SQS | JMS Queue / Anypoint MQ |
| Procesador | Lambda | Mule Flow / TIBCO BW Process |
| Trigger / enlace | Event Source Mapping | Inbound Endpoint / JMS Receiver |
| Evento | Mensaje JSON / SQS event | Mule Message / TIBCO JMS Message |
| Permisos | IAM Role | Policy / Client ID |
| Logs | CloudWatch Logs | Mule logs / TIBCO Administrator |
| Entorno local | LocalStack | Anypoint Studio / TIBCO Designer |
| Infraestructura como código | AWS CLI / CloudFormation | Anypoint Studio deploy |

---

## Troubleshooting

| Síntoma | Causa | Solución |
|---------|-------|----------|
| LocalStack no arranca | Puerto 4566 ocupado | `netstat -ano \| findstr :4566` y mata el proceso |
| AWS CLI no conecta con LocalStack | Falta `--network=host` | Añade `--network=host` al comando `podman run` |
| Lambda no se invoca al enviar mensaje | Falta event source mapping | Ejecuta `create_trigger.ps1` |
| Lambda se invoca pero el mensaje no se elimina | La Lambda lanza excepción | Revisa `verify_logs.ps1` y corrige `index.py` |
| Contenedor localstack-pipeline ya existe | Ejecución previa sin teardown | Usa `start_localstack.ps1 -Recreate` |

---

## Resumen de aprendizaje

Al completar este pipeline has practicado:

1. **Event-Driven Architecture (EDA)** — desacoplamiento total entre productor y consumidor mediante una cola
2. **AWS SQS** — creación de colas, envío/recepción de mensajes, URLs vs ARNs
3. **AWS Lambda** — empaquetado, despliegue, handler events, ciclo de vida de invocación
4. **Event Source Mapping** — cómo conectar un servicio productor con un consumidor serverless
5. **LocalStack** — emulación local de servicios AWS, health checks, idempotencia
6. **Podman** — contenedores rootless, network modes, volúmenes bind mount
7. **Automatización PowerShell** — scripts idempotentes, orquestación, verificación post-ejecución
8. **Patrón de middleware** — equivalentes entre AWS serverless y MuleSoft/TIBCO
