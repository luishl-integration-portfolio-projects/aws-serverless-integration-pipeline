# AWS Serverless Integration Pipeline (EDA)

Este repositorio contiene un proyecto de **Arquitectura Orientada a Eventos (EDA)** que simula un pipeline de integración empresarial de alta disponibilidad para un comercio electrónico. El objetivo es procesar pedidos de forma asíncrona y desacoplada utilizando servicios nativos de AWS.

El entorno está diseñado para ejecutarse de forma 100% local y gratuita utilizando **Podman** y **LocalStack**, esquivando restricciones de red corporativas.

---

## 📐 Arquitectura del Sistema

El flujo de integración replica patrones clásicos de Middleware (como los utilizados en MuleSoft o TIBCO Business Works):

1. **Ingesta (Próxima Fase):** AWS API Gateway recibe las peticiones HTTP con los datos del pedido.
2. **Desacoplamiento (Fase 1 - OK):** Los pedidos se encolan en **AWS SQS** para garantizar la persistencia y absorción de picos de tráfico.
3. **Procesamiento (Fase 2 - En curso):** Una función **AWS Lambda** desarrollada en **Python 3.12** se activa automáticamente ante eventos de la cola para procesar el negocio.

---

## 🛠️ Guía de Ejecución Local (Playbook)

Para levantar la infraestructura en un entorno corporativo con restricciones, ejecutar los siguientes comandos desde la raíz del proyecto:

### 1. Inicializar el entorno local (Terminal 1)
```powershell
podman run --rm -it -p 4566:4566 -p 4510-4559:4510-4559 localstack/localstack:3.0

### 2. Crear la cola de mensajería (SQS)
```powershell
podman run --rm -it --network=host -e AWS_ACCESS_KEY_ID=mock -e AWS_SECRET_ACCESS_KEY=mock -e AWS_DEFAULT_REGION=us-east-1 amazon/aws-cli --endpoint-url=[http://127.0.0.1:4566](http://127.0.0.1:4566) sqs create-queue --queue-name cola-pedidos-ecommerce

### 3. Desplegar el procesador (AWS Lambda)
Primero, empaquetar el código Python:

```powershell
Compress-Archive -Path src/index.py -DestinationPath src/funcion_lambda.zip -Force

Luego, registrar la función en LocalStack:

```powershell
podman run --rm -it --network=host -v "${PWD}/src:/workspace" -e AWS_ACCESS_KEY_ID=mock -e AWS_SECRET_ACCESS_KEY=mock -e AWS_DEFAULT_REGION=us-east-1 amazon/aws-cli --endpoint-url=[http://127.0.0.1:4566](http://127.0.0.1:4566) lambda create-function --function-name procesador-pedidos-lambda --runtime python3.12 --role arn:aws:iam::000000000000:role/lambda-ex --handler index.lambda_handler --zip-file fileb:///workspace/funcion_lambda.zip