# Troubleshooting: Problemas y Resoluciones

Cronica de los problemas encontrados durante el desarrollo del pipeline, ordenados
por orden de aparicion.

---

## 1. PowerShell no puede alcanzar LocalStack via 127.0.0.1

**Sintoma:** `Invoke-RestMethod -Uri "http://127.0.0.1:4566/_localstack/health"` falla
con "No es posible conectar con el servidor remoto", aunque el contenedor esta corriendo
dentro de WSL2.

**Causa:** Podman en Windows solo reenvia los puertos a IPv6 (`[::1]:4566`), no a IPv4
(`127.0.0.1:4566`). La IP interna de WSL2 (`172.x.x.x`) funciona directamente.

**Resolucion:** El health check prueba multiples direcciones en orden: `127.0.0.1`,
`localhost`, `[::1]`, y la IP de WSL2 detectada dinamicamente con
`wsl -- ip -4 addr show eth0`.

**Archivo:** `scripts/start_localstack.ps1` — funcion `Get-LocalStackHealthUri`

---

## 2. PowerShell interpreta $variable:text como referencia de variable

**Sintoma:** Error `La referencia de variable no es valida. El caracter ':' no va seguido
de un caracter de nombre de variable valido.` en lineas como:
```powershell
Write-Host "--- Step $Num: $Label ---"
```

**Causa:** PowerShell interpreta `$Label:` como una referencia a la variable `$Label:`
(incluyendo los dos puntos como parte del nombre).

**Resolucion:** Usar `${Label}` para delimitar el nombre, o el operador format `-f`:
```powershell
Write-Host ("--- Step {0}: {1} ---" -f $Num, $Label)
```

**Archivos:** Multiples scripts.

---

## 3. LocalStack reporta servicios como "running" o "available" segun la version

**Sintoma:** El health check falla aunque LocalStack esta funcionando. Servicios aparecen
como `available` en v3.0.2 y como `running` en v4.0.

**Causa:** LocalStack cambio el estado reportado por el health endpoint entre versiones.

**Resolucion:** Aceptar ambos estados: `$health.services.sqs -in @("available", "running")`.

**Archivo:** `scripts/start_localstack.ps1` — linea de health check.

---

## 4. Invoke-Expression rompe el quoting de argumentos

**Sintoma:** Comandos como `lambda create-function --zip-file fileb:///workspace/...`
fallan con exit code 252 o producen salida vacia cuando se usan con `Invoke-Expression`.

**Causa:** `Invoke-Expression "& $fullCmd"` re-parsea el string como codigo PowerShell,
perdiendo las comillas anidadas y rompiendo argumentos que contienen espacios o
caracteres especiales.

**Resolucion:** Usar direct `& podman $argsArray` con splatting:
```powershell
$podmanBase = @("run","--rm","--network=host","amazon/aws-cli","--endpoint-url=...")
$result = & podman $podmanBase lambda create-function --function-name ...
```

**Archivos:** `scripts/lambda/deploy_lambda.ps1`, `scripts/lambda/create_trigger.ps1`,
`scripts/lambda/verify_logs.ps1`, `scripts/teardown.ps1`.

---

## 5. JSON con espacios en --message-body de SQS se rompe

**Sintoma:** Al enviar un mensaje SQS con `--message-body '{"productos": ["Widget A", ...]}'`,
el AWS CLI recibe argumentos partidos: `[ERROR]: Unknown options: B], moneda: EUR}, A, Gadget`

**Causa:** El JSON contiene espacios en valores de arrays. PowerShell no escapa correctamente
las comillas dobles anidadas al pasar argumentos a procesos externos (podman).

**Resolucion:** Escribir el body a un archivo temporal y usar `--message-body file:///payload/message.json`.
El archivo se monta via `-v` en el contenedor.

**Archivo:** `scripts/queues/publish_message_to_queue.ps1`

---

## 6. Emojis en consola PowerShell se muestran como caracteres rotos

**Sintoma:** Caracteres como `â` aparecen en lugar de emojis.

**Causa:** La terminal de Windows PowerShell no soporta UTF-8 correctamente para caracteres
multi-byte como emojis. El primer byte del UTF-8 sequence se muestra literalmente.

**Resolucion:** Reemplazar todos los emojis por marcadores ASCII: `[OK]`, `[ERR]`, `[..]`, `[WARN]`.

**Archivos:** Todos los scripts `.ps1` y `README.md`.

---

## 7. Lambda se despliega pero queda en estado Pending

**Sintoma:** La funcion se crea con `State: "Pending"` y las invocaciones fallan con
"ResourceConflictException: The function is currently in the following state: Pending".

**Causa:** LocalStack 3.x+ (como AWS real) crea las funciones de forma asincrona. El
event source mapping y los mensajes llegan antes de que la funcion este lista.

**Resolucion:** Anadir espera con `lambda wait function-active-v2 --function-name ...`
despues de `create-function`/`update-function-code`.

**Archivo:** `scripts/lambda/deploy_lambda.ps1` — paso `[3/3]`.

---

## 8. LocalStack 3.0.2 no puede conectar Lambda executors con Podman

**Sintoma:** El contenedor ejecutor Lambda se crea y reporta `ready`, recibe el
`invoke-payload`, pero nunca completa la ejecucion. El contenedor se queda "Up"
indefinidamente y el mensaje SQS se re-encola tras 30 segundos.

**Causa:** LocalStack configura `LOCALSTACK_HOSTNAME=169.254.1.2` (link-local) para que
los ejecutores se comuniquen con la API de LocalStack. Docker soporta anadir esta IP
al bridge via API; Podman no. El ejecutor ejecuta el codigo pero no puede reportar el
resultado.

**Intentos fallidos:**
| Enfoque | Resultado |
|---------|-----------|
| `--network=host` en contenedor principal | `Unable to get main container IP address` |
| `LAMBDA_DOCKER_NETWORK=host` | No soportado por el nuevo Lambda provider |
| `PROVIDER_OVERRIDE_LAMBDA=legacy` | Proveedor legacy eliminado desde 3.0.0 |
| `LAMBDA_REMOTE_DOCKER=false` | No cambia el hostname usado |
| `HOSTNAME_FROM_LAMBDA=host.containers.internal` | Podman rechaza la IP `<nil>` |
| `HOSTNAME_FROM_LAMBDA=10.88.0.1` (gateway IP) | Funciona pero IP hardcodeada |

**Resolucion definitiva (LocalStack 4.0.3 + red personalizada):**
1. Actualizar a `localstack/localstack:4.0`
2. Crear una red Podman personalizada: `podman network create ls-net`
3. Ejecutar LocalStack en esa red: `--network ls-net`
4. Configurar `LAMBDA_DOCKER_NETWORK=ls-net` para que los ejecutores usen la misma red
5. LocalStack encuentra su propia IP en la red `ls-net` y la pasa a los ejecutores

**Archivo:** `scripts/start_localstack.ps1` — steps 2-3.

---

## 9. El prefijo de los contenedores ejecutores Lambda cambia segun la configuracion de red

**Sintoma:** `verify_logs.ps1` y `cleanup_containers.ps1` no encuentran los contenedores
ejecutores. El prefijo cambio de `localstack-pipeline-lambda-*` a `localstack-main-lambda-*`.

**Causa:** LocalStack deriva el prefijo del nombre del contenedor principal. Con
`--network=host`, LocalStack detecta el contenedor principal como "localstack-main".
Con `--network ls-net`, lo detecta como "localstack-pipeline".

**Resolucion:** Usar `--filter "name=procesador-pedidos-lambda"` que coincide con el
nombre de la funcion, siempre presente independientemente del prefijo.

**Archivos:** `scripts/lambda/verify_logs.ps1`, `scripts/cleanup_containers.ps1`,
`scripts/dump_logs.ps1`.

---

## 10. UTF-8 BOM en mensajes SQS rompe json.loads() de Python

**Sintoma:** La Lambda se ejecuta pero falla con:
```
JSONDecodeError: Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)
```

**Causa:** El mensaje SQS incluye un BOM (`\ufeff`) al inicio del body JSON. El
`json.loads()` de Python no lo maneja por defecto.

**Resolucion:** Limpiar el BOM antes de parsear: `body_str.lstrip('\ufeff')`.

**Archivo:** `src/index.py` — linea 9.

---

## 11. Duplicacion de pasos en deploy_all.ps1

**Sintoma:** Los pasos 2 (Create SQS), 3 (Package Lambda) y 4 (Deploy Lambda) se
ejecutan dos veces al usar `deploy_all.ps1`.

**Causa:** Error de copy-paste al editar el script.

**Resolucion:** Eliminar el bloque duplicado (lineas 82-99 del original).

**Archivo:** `scripts/deploy_all.ps1`.

---

## 12. El health check de `start_localstack.ps1` se queda colgado con Lambda=False

**Sintoma:** SQS aparece como disponible pero Lambda nunca pasa de `False`, aunque
LocalStack logs muestran que ambos servicios estan activos.

**Causa:** En algunas versiones de LocalStack, el servicio Lambda tarda mas en
inicializarse que SQS. El health check tiene un timeout de 40 intentos x 2s = 80s,
pero en casos extremos puede necesitar mas.

**Resolucion:** El health check acepta tanto `"available"` como `"running"`. Si
persiste, aumentar `$attempts -lt 40` o anadir `-e SERVICES=lambda,sqs,logs` para
acelerar la inicializacion.

**Archivo:** `scripts/start_localstack.ps1` — funcion `Wait-ForLocalStack`.

---

## Resumen de cambios de configuracion

| Variable | Valor final | Proposito |
|----------|------------|-----------|
| `LAMBDA_EXECUTOR` | `docker` | Usar contenedores Docker para ejecutar Lambdas |
| `LAMBDA_DOCKER_NETWORK` | `ls-net` | Red personalizada para conectar ejecutores con LocalStack |
| `DEBUG` | `1` | Logs detallados de LocalStack |
| `SERVICES` | `lambda,sqs,logs` | Solo iniciar los servicios necesarios |

| Flag de Podman | Proposito |
|----------------|-----------|
| `--network ls-net` | Conectar LocalStack a la red personalizada |
| `-p 4566:4566` | Exponer puerto de la API |
| `-p 4510-4559:4510-4559` | Exponer puertos de servicios internos |
| `-v /var/run/docker.sock:/var/run/docker.sock` | Montar socket Docker/Podman para crear ejecutores |
