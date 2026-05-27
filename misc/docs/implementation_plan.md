# Implementation Plan (Ejecutado)

## Problema original

El flujo de trabajo requería ejecutar 5+ comandos manuales en múltiples terminales sin orquestación. **No existía el trigger SQS → Lambda**, por lo que la función Lambda nunca se invocaba automáticamente al llegar mensajes a la cola.

## Objetivo

Un solo script (`deploy_all.ps1`) que desde **estado limpio** levante el pipeline completo:
1. Arrancar LocalStack (detached)
2. Esperar a que esté listo (health check)
3. Crear cola SQS
4. Empaquetar y desplegar la Lambda
5. Crear el event source mapping (trigger SQS → Lambda) — **la pieza faltante**
6. Enviar un mensaje de prueba
7. Verificar que la Lambda lo procesó

## Lo implementado

### Scripts creados (7 nuevos + 3 actualizados)

| Script | Estado | Propósito |
|--------|--------|-----------|
| `scripts/start_localstack.ps1` | **NUEVO** | Arranca LocalStack en background + health check con reintentos |
| `scripts/lambda/package_lambda.ps1` | **NUEVO** | Comprime `src/index.py` → `src/funcion_lambda.zip` |
| `scripts/lambda/deploy_lambda.ps1` | **NUEVO** | Crea o actualiza la Lambda (idempotente) |
| `scripts/lambda/create_trigger.ps1` | **NUEVO** | Crea event source mapping SQS → Lambda |
| `scripts/lambda/verify_logs.ps1` | **NUEVO** | Inspecciona logs del contenedor y CloudWatch |
| `scripts/deploy_all.ps1` | **NUEVO** | Orquestador: ejecuta todo el pipeline secuencialmente |
| `scripts/teardown.ps1` | **NUEVO** | Limpia todos los recursos y para LocalStack |
| `scripts/queues/create_queue.ps1` | **ACTUALIZADO** | Ahora es idempotente con output estructurado |
| `scripts/queues/publish_message_to_queue.ps1` | **ACTUALIZADO** | Acepta parámetros, muestra MessageId |
| `scripts/queues/receive_message.ps1` | **ACTUALIZADO** | Muestra los mensajes en cola de forma legible |

### Pieza clave: Event Source Mapping

```
aws lambda create-event-source-mapping \
  --function-name procesador-pedidos-lambda \
  --event-source-arn arn:aws:sqs:us-east-1:000000000000:cola-pedidos-ecommerce \
  --enabled
```

Este comando es el que hace que la Lambda sea **reactiva** a los mensajes de SQS. Sin él, los mensajes se acumulan en la cola y la Lambda nunca se ejecuta.

### Estructura final de scripts

```
scripts/
├── start_localstack.ps1
├── deploy_all.ps1                  ← Un solo comando para todo
├── teardown.ps1
│
├── queues/
│   ├── create_queue.ps1
│   ├── publish_message_to_queue.ps1
│   └── receive_message.ps1
│
└── lambda/
    ├── package_lambda.ps1
    ├── deploy_lambda.ps1
    ├── create_trigger.ps1
    └── verify_logs.ps1
```

## Cómo usar

```powershell
# Despliegue completo
.\scripts\deploy_all.ps1

# O paso a paso (para aprender):
.\scripts\start_localstack.ps1
.\scripts\queues\create_queue.ps1
.\scripts\lambda\package_lambda.ps1
.\scripts\lambda\deploy_lambda.ps1
.\scripts\lambda\create_trigger.ps1
.\scripts\queues\publish_message_to_queue.ps1
.\scripts\lambda\verify_logs.ps1

# Limpieza
.\scripts\teardown.ps1
```

## Próximas fases (plan fututo)

| Fase | Adición |
|------|---------|
| 3 | Tabla DynamoDB + Lambda escribe pedidos en DB |
| 4 | API Gateway como punto de entrada HTTP |
| 5 | DLQ separada para mensajes fallidos |
