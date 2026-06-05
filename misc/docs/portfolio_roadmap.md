# Portfolio Roadmap

Hoja de ruta para convertir este proyecto en un portafolio competitivo para
posiciones AWS / Cloud Developer. Organizado por categorias y priorizado por
impacto en entrevistas.

**Estado actual:** Proyecto funcional con CI/CD pipeline operativo en GitHub
Actions contra LocalStack. Documentacion extensa en README.

**Proximo hito:** Tests automaticos + empaquetado profesional de Python.

---

## Leyenda

| Icono | Significado |
|-------|-------------|
| ✅ | Completado |
| 🔷 | No iniciado |
| 🔶 | En progreso |
| ⏱ | Esfuerzo estimado |
| 📈 | Impacto en portfolio |

---

## 1. Tests automatizados (prioridad maxima)

Sin tests, el proyecto parece un ejercicio, no un producto de ingenieria.

### 1.1 Unit tests para Lambdas — 🔷

Escribir tests con `pytest` + `moto` (mockea los servicios AWS) para las tres
funciones Lambda:

- **`src/index.py`** — testear que:
  - Un mensaje SQS valido se persiste correctamente en DynamoDB
  - Un mensaje con JSON malformado no rompe el handler
  - Un mensaje sin `id_pedido` se maneja con gracia
  - `parse_float=Decimal` convierte correctamente los floats
- **`src/api_handler.py`** — testear que:
  - Un POST valido reenvia el payload a SQS
  - Un JSON invalido devuelve 500 sin crash
- **`src/orders_crud.py`** — testear que:
  - GET /orders devuelve lista (incluso vacia)
  - GET /orders/{id} devuelve 404 si no existe
  - PUT /orders/{id} actualiza solo los campos enviados
  - DELETE /orders/{id} funciona y luego GET devuelve 404

```
⏱ 3-4 horas
📈 Muy alto — es lo primero que preguntan en entrevistas tecnicas
```

### 1.2 Integration test contra LocalStack — 🔷

Un test que levante LocalStack, ejecute `terraform apply`, haga peticiones
reales HTTP a la API, verifique DynamoDB, y haga `terraform destroy`.

```
⏱ 2-3 horas (gran parte ya esta en el CI/CD)
📈 Alto — diferencia entre "se que deberia" y "lo hago"
```

### 1.3 CI/CD gate — ✅

El workflow de GitHub Actions ya:
- Ejecuta `terraform fmt -check` (estilo)
- Ejecuta `terraform validate` (sintaxis)
- Ejecuta `terraform plan` (previsualizacion)
- Despliega en LocalStack y corre 7 tests de integracion via curl
- Destruye los recursos al terminar

```
⏱ Completado
📈 Muy alto — pocos candidatos junior llevan CI/CD en su portfolio
```

---

## 2. Calidad de codigo Python

### 2.1 Package structure + requirements.txt — 🔷

Actualmente las Lambdas son archivos sueltos. En produccion se estructura asi:

```
src/
├── processor/
│   ├── __init__.py
│   ├── handler.py          # Lambda handler
│   ├── dynamodb_repo.py    # Capa de datos
│   └── models.py           # Data classes / validacion
├── proxy/
│   ├── __init__.py
│   └── handler.py
├── crud/
│   ├── __init__.py
│   └── handler.py
└── requirements.txt        # boto3, pytest, moto, etc.
```

Ademas, anadir `requirements.txt` con dependencias y usar `pip install -t`
para empaquetar (o Lambda Layers).

```
⏱ 2-3 horas
📈 Alto — codigo monolitico vs modular marca la diferencia
```

### 2.2 Manejo de errores robusto — 🔷

Mejoras necesarias:

- **Input validation:** La CRUD Lambda asume que `event['pathParameters']['id']`
  es numerico — `int()` hara crash si no lo es.
- **DLQ (Dead Letter Queue):** Los mensajes que fallen repetidamente deben ir a
  una cola separada para debug, no perderse.
- **Try/except granular:** La Lambda procesadora ya tiene try/except pero los
  mensajes de error son genericos. Incluir el `id_pedido` y el `RequestId` en
  cada error.
- **Manejo de SQS partial failures:** Si un lote de 10 mensajes falla en el
  item 5, los items 1-4 ya se procesaron pero SQS los reintentara (a menos que
  se use `report_batch_item_failures`).

```
⏱ 2-3 horas
📈 Muy alto — resiliencia es un tema recurrente en entrevistas AWS
```

### 2.3 Structured logging + X-Ray — 🔷

Remplazar `print()` por:

```python
import logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

logger.info({
    "event": "ORDER_PROCESSED",
    "order_id": 1001,
    "client": "test",
    "amount": 99.90,
    "request_id": context.aws_request_id,
})
```

Ademas, activar **AWS X-Ray** en las Lambdas y anadir segmentos/subsegmentos
para tracing de extremo a extremo (API Gateway → Lambda → SQS → Lambda → DynamoDB).

```
⏱ 2 horas
📈 Alto — muestra madurez en observabilidad
```

---

## 3. Infraestructura y DevOps

### 3.1 S3 backend para Terraform state — 🔷

El estado de Terraform (`terraform.tfstate`) esta en el disco local y se
pierde al destruir el CI. En produccion se almacena en S3 con DynamoDB para
locking. En LocalStack se puede emular:

```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-state-eda"
    key            = "pipeline/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
  }
}
```

Esto ademas hace que el CI sea **verdaderamente portable**: cualquier runner
puede recuperar el estado.

```
⏱ 1 hora
📈 Medio — muestra que entiendes state management, aunque no es visible en demos
```

### 3.2 Docker Compose / Podman Compose — 🔷

Crear `compose.yaml` en la raiz del proyecto:

```yaml
services:
  localstack:
    image: localstack/localstack:4.0.3
    ports:
      - "4566:4566"
      - "4510-4559:4510-4559"
    environment:
      SERVICES: lambda,sqs,dynamodb,apigateway,iam,logs,cloudwatch
      LAMBDA_DOCKER_NETWORK: ls-net
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - ls-net

networks:
  ls-net:
    driver: bridge
```

```
⏱ 30 min
📈 Medio — demuestra conocimiento de contenerizacion
```

### 3.3 CORS en API Gateway — 🔷

Anadir metodo `OPTIONS` a los recursos de API Gateway con cabeceras
`Access-Control-Allow-Origin: *` y las cabeceras/metodos permitidos.

```
⏱ 15 min
📈 Bajo — pero necesario si alguien prueba desde navegador
```

---

## 4. Presentacion del portfolio

### 4.1 Traduccion a ingles — 🔷

Todo el proyecto debe estar en ingles: README, codigo, scripts, comentarios,
documentos en `misc/docs/`, nombres de variables, mensajes de log.

Un portfolio en ingles es **requisito no negociable** para aplicar a empresas
internacionales o equipos globales, incluyendo AWS.

```
⏱ 3-4 horas (esfuerzo unico)
📈 Muy alto — sin esto, el proyecto esta invisible para reclutadores internacionales
```

### 4.2 GitHub profile README — 🔷

Crear `profile/README.md` (o el `README.md` del perfil de GitHub) que muestre
el proyecto como caso principal, con:
- Badges de estado del CI/CD
- Diagrama de arquitectura
- Enlace directo al repo
- 3-5 bullet points de tecnologias demostradas

```
⏱ 1 hora
📈 Alto — es la landing page de tu perfil de GitHub
```

### 4.3 Limpiar archivos residuales — 🔷

Eliminar del repositorio:
- Logs de LocalStack en `logs/` (ya en `.gitignore`? verificar)
- Archivos `.zip` de las Lambdas (ya en `.gitignore` ✅)
- Directorio `terraform/.terraform/` (ya en `.gitignore` ✅)
- `terraform/terraform.tfstate` (ya en `.gitignore` ✅)
- Archivos temporales de pruebas

Y commitear el `.gitignore` actualizado si falta alguna entrada.

```
⏱ 15 min
📈 Bajo — pero un repo limpio causa buena primera impresion
```

---

## 5. Mejoras de arquitectura

### 5.1 Bug: duplicacion en deploy_all.ps1 — 🔷

**Problema:** El script ejecuta los pasos 2 (Create SQS), 3 (Package Lambda)
y 4 (Deploy Lambda) dos veces por un bloque copiado por error.

**Impacto:** El despliegue tarda el doble. Funcional porque los sub-scripts
son idempotentes, pero incorrecto.

```
⏱ 5 min
📈 Bajo — solo calidad de codigo interno
```

### 5.2 Lambda Layers para dependencias — 🔷

En lugar de empaquetar `boto3` con cada Lambda (que de hecho ya viene en el
runtime), crear un Layer con dependencias adicionales si las hubiera (p.ej.,
`requests`, `pydantic` para validacion). Demuestra conocimiento de Lambda Layers.

```
⏱ 30 min
📈 Medio — conceptos de empaquetado y reutilizacion
```

### 5.3 VPC / networking — 🔷

Configurar las Lambdas dentro de una VPC simulada (LocalStack soporta VPCs).
No es necesario para el pipeline actual (SQS y DynamoDB son accesibles via
Internet), pero muestra que entiendes aislamiento de red, subnets, security
groups, VPC Endpoints (VPCe) para servicios AWS.

```
⏱ 1-2 horas
📈 Alto — el networking es un punto debil comun en candidatos
```

---

## Resumen de prioridades

| # | Tarea | Esfuerzo | Impacto | Depende de |
|---|-------|----------|---------|------------|
| 1 | **Tests unitarios** (pytest + moto) | 3-4h | 🔥 Muy alto | — |
| 2 | **Traduccion a ingles** | 3-4h | 🔥 Muy alto | — |
| 3 | **Package structure + requirements.txt** | 2-3h | 🔥 Alto | — |
| 4 | **Structured logging + X-Ray** | 2h | 🔥 Alto | — |
| 5 | **Manejo de errores + DLQ** | 2-3h | 🔥 Muy alto | — |
| 6 | **S3 backend para Terraform** | 1h | 📊 Medio | — |
| 7 | **Integration tests (complemento)** | 2-3h | 🔥 Alto | Tests unitarios |
| 8 | **VPC / networking** | 1-2h | 🔥 Alto | — |
| 9 | **Lambda Layers** | 30min | 📊 Medio | Package structure |
| 10 | **Docker Compose** | 30min | 📊 Medio | — |
| 11 | **CORS** | 15min | 📊 Bajo | — |
| 12 | **GitHub profile README** | 1h | 🔥 Alto | Traduccion |
| 13 | **Bug deploy_all.ps1** | 5min | 📊 Bajo | — |
| 14 | **Limpiar archivos residuales** | 15min | 📊 Bajo | — |

## Orden recomendado de ejecucion

```
Semana 1:  Tests unitarios (1) + DLQ/errores (5)
Semana 2:  Package structure (3) + structured logging (4)
Semana 3:  Traduccion a ingles (2) + GitHub profile (12)
Semana 4:  Integration tests (7) + VPC (8) + S3 backend (6)
Semana 5:  Lambda Layers (9) + Docker Compose (10) + CORS (11) + Bugs (13, 14)
```

Con las semanas 1-3 completadas, el proyecto es competitivo para cualquier
posicion cloud-serverless junior/semi-senior.
