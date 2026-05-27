# TODOs: Mejoras pendientes

Lista de mejoras identificadas para llevar el proyecto al siguiente nivel.

---

## 1. Corregir duplicacion de pasos en deploy_all.ps1

**Problema:** El script ejecuta los pasos 2 (Create SQS), 3 (Package Lambda) y 4 (Deploy
Lambda) dos veces debido a un bloque duplicado por error de edicion.

**Impacto:** El despliegue tarda el doble de lo necesario, aunque es funcional porque
todos los sub-scripts son idempotentes.

**Tarea:** Eliminar el bloque duplicado (lineas 82-99 aprox del original).

---

## 2. Anadir DynamoDB como almacenamiento persistente

**Descripcion:** Conectar la Lambda procesadora a una tabla DynamoDB para almacenar los
pedidos. LocalStack soporta DynamoDB gratis.

**Cambios necesarios:**
- Agregar `dynamodb` a la variable `SERVICES` en `start_localstack.ps1`
- Script `scripts/dynamodb/create_table.ps1` para crear la tabla `pedidos`
- Modificar `src/index.py` para que escriba el pedido en DynamoDB ademas de printearlo
- Agregar paso en `deploy_all.ps1` para crear la tabla antes de desplegar la Lambda

**Resultado:** La Lambda procesadora hara un CRUD real, mostrando integracion entre
3 servicios AWS: SQS -> Lambda -> DynamoDB.

---

## 3. Anadir Dead Letter Queue (DLQ)

**Descripcion:** Configurar una segunda cola SQS como Dead Letter Queue para mensajes
que fallen repetidamente. Es un patron de resiliencia estandar en AWS.

**Cambios necesarios:**
- Script `scripts/queues/create_dlq.ps1` para crear la cola DLQ
- Modificar `create_trigger.ps1` o crear config de `redrive-policy` en la cola principal
- Modificar `teardown.ps1` para limpiar la DLQ

**Resultado:** El pipeline maneja fallos de forma profesional, demostrando conocimiento
de patrones de arquitectura cloud.

---

## 4. Tests automatizados

**Descripcion:** Crear tests que verifiquen el pipeline completo sin intervention
manual.

**Cambios necesarios:**
- Script `scripts/test_pipeline.ps1` que:
  1. Envia un mensaje a SQS directamente (o via API Gateway)
  2. Espera a que la Lambda lo procese
  3. Verifica los logs de CloudWatch
  4. Verifica que la cola queda vacia
  5. Reporta exito/fallo con codigo de salida
- Compatibilidad con CI/CD (Azure Pipelines, GitHub Actions, etc.)

**Resultado:** El proyecto se puede integrar en un pipeline CI/CD y demostrar
habilidades de testing.

---

## 5. Manejo de errores en src/index.py

**Descripcion:** La Lambda procesadora no tiene try/except. Si el JSON del mensaje
es invalido o falta un campo requerido, la funcion explota sin registro util.

**Cambios necesarios:**
- Envolver el cuerpo del handler en try/except
- Loggear errores con contexto (pedido ID, causa, etc.)
- Propagar el error correctamente para que SQS reintente y eventualmente pase a DLQ

**Resultado:** La Lambda es robusta y permite debugging efectivo.

---

## 6. Docker Compose / Podman Compose

**Descripcion:** Anadir un fichero `compose.yaml` para arrancar LocalStack con un solo
comando (`podman-compose up`), mostrando habilidades de contenerizacion.

**Beneficio:** Simplifica el arranque y demuestra conocimiento de Docker Compose como
herramienta de orquestacion.

---

## 7. Mejorar logs de la Lambda proxy

**Descripcion:** La Lambda proxy (`api_handler.py`) podria loggear mas informacion:
tiempo de respuesta de SQS, tamano del payload, errores de parsing, etc.

**Beneficio:** Mejora la observabilidad del pipeline y facilita el debugging cuando
algo falla.

---

## 8. Configurar CORS en API Gateway

**Descripcion:** Anadir cabeceras CORS al metodo OPTIONS y a la respuesta 200 del
metodo POST en API Gateway para permitir llamadas desde navegador.

**Beneficio:** Permite probar el endpoint desde aplicaciones web (SPA, React, etc.)
y demuestra conocimiento de CORS en API Gateway.

---

## Prioridad sugerida

| # | Tarea | Esfuerzo | Impacto |
|---|-------|----------|---------|
| 1 | Corregir duplicacion | 5 min | Alto (calidad del codigo) |
| 5 | Manejo de errores en index.py | 15 min | Alto (robustez) |
| 2 | DynamoDB | 1-2 h | Muy alto (portfolio) |
| 4 | Tests | 2-3 h | Muy alto (portfolio) |
| 3 | DLQ | 30 min | Medio (resiliencia) |
| 6 | Compose | 30 min | Medio (contenerizacion) |
| 7 | Logs proxy | 10 min | Bajo (observabilidad) |
| 8 | CORS | 15 min | Bajo (completitud) |
