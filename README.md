# AWS Serverless Integration Pipeline (EDA)

Enterprise integration pipeline based on **Event-Driven Architecture (EDA)**
for an e-commerce platform, running 100% locally with **Podman** and **LocalStack**. It replicates classic
middleware patterns (MuleSoft, TIBCO Business Works) using native AWS services.

---

## Architecture

```
Postman / curl
     |
     v
API Gateway (REST)                 <- HTTP ingestion phase
     |        /orders POST
     v
Lambda proxy (api_handler.py)      <- Forwards to SQS
     |
     v
SQS                                <- Phase 1: Decoupling (queue)
     |        cola-pedidos-ecommerce
     v
Processor Lambda                   <- Phase 2: Processing (triggered by SQS)
     |        (index.lambda_handler)
     v
CloudWatch Logs                    <- Execution logs
```

### Data flow

1. An order arrives as an HTTP POST to API Gateway `/orders`
2. API Gateway invokes the proxy Lambda via `AWS_PROXY` integration
3. The proxy Lambda enqueues the order in SQS using boto3
4. SQS retains the message until a consumer processes it
5. The processor Lambda is triggered **automatically** (SQS event source mapping)
6. Lambda extracts the order fields, transforms them, and records them in CloudWatch
7. SQS deletes the message after a successful execution

### Note about LocalStack 4.x

LocalStack 4.x with Docker enabled launches **one Podman container per Lambda
invocation** (e.g. `localstack-pipeline-lambda-procesador-pedidos-lambda-<hash>`). The logs
from each execution go to those containers and to CloudWatch Logs, not to the main
LocalStack container. The `verify_logs.ps1` and `dump_logs.ps1` scripts
inspect them automatically.

---

## What has been automated (this project)

| Before (manual) | Now (automated) |
|----------------|----------------------|
| Starting LocalStack in a separate terminal | `start_localstack.ps1` — starts in background + waits until ready |
| Creating SQS queue, packaging Lambda, deploying: 3 separate commands | `package_lambda.ps1` + `deploy_lambda.ps1` — idempotent create or update |
| **The SQS-Lambda trigger did not exist** — Lambda never fired on its own | `create_trigger.ps1` — connects SQS -> Lambda with `create-event-source-mapping` |
| Lambda was deployed but remained in `Pending` state and failed on invocation | `deploy_lambda.ps1` now waits for the function to become `Active` |
| No way to view Lambda logs | `verify_logs.ps1` — inspects executor containers + CloudWatch |
| Sending JSON with spaces in the SQS body broke PowerShell quoting | `publish_message_to_queue.ps1` uses a temporary file for the body |
| The full pipeline required 5+ commands in exact order | `deploy_all.ps1` — complete deployment in a single command |
| Executor containers accumulated between tests | `cleanup_containers.ps1` — removes them without restarting LocalStack |
| No way to get a full log dump | `dump_logs.ps1` — dumps everything to a timestamped file |
| No HTTP entry point for Postman testing | `create_rest_api.ps1` — creates API Gateway REST with Lambda proxy |
| Manual container cleanup | `teardown.ps1` — deletes resources and stops LocalStack |

---

## Prerequisites

- **Windows** with PowerShell 5.1+
- **Podman** installed (`podman --version`)
- WSL2 with updated Linux kernel (Podman runs on WSL)
- Ports **4566** and **4510-4559** available

---

## Scripts map

```
scripts/
├── start_localstack.ps1           # Starts LocalStack in background + health check
├── deploy_all.ps1                 # ORCHESTRATOR: executes the entire pipeline sequentially
├── teardown.ps1                   # Cleans up all resources and stops LocalStack
├── cleanup_containers.ps1         # Removes only Lambda executor containers
├── dump_logs.ps1                  # Dumps all logs to logs/<timestamp>.log
│
├── queues/
│   ├── create_queue.ps1           # Creates SQS queue (idempotent)
│   ├── publish_message_to_queue.ps1  # Sends a test order to the queue
│   └── receive_message.ps1        # Reads messages from the queue (debug)
│
├── lambda/
│   ├── package_lambda.ps1         # Compresses index.py -> funcion_lambda.zip
│   ├── deploy_lambda.ps1          # Creates or updates Lambda function + waits for Active
│   ├── create_trigger.ps1         # Connects SQS -> Lambda (event source mapping)
│   └── verify_logs.ps1            # Shows execution logs (container + executors)
│
└── api/
    └── create_rest_api.ps1        # Creates API Gateway REST + Lambda proxy -> SQS
```

---

## Step-by-step execution

### 1. Full deployment (single command)

```powershell
.\scripts\deploy_all.ps1
```

Steps executed:
0. Clean up executor containers from previous runs
1. Start LocalStack (with `ls-net`, Docker socket, lambda+sqs+logs+apigateway+iam services)
2. Create SQS queue `cola-pedidos-ecommerce`
3. Create API Gateway REST + Lambda proxy for HTTP ingestion
4. Package processor Lambda (`index.py`)
5. Deploy processor Lambda
6. Create SQS -> Lambda event source mapping
7. Send test message to SQS
8. Verify execution logs

### 2. Step-by-step execution (learning mode)

#### Step 1: Start LocalStack

```powershell
.\scripts\start_localstack.ps1
```

**What it does:**
- Launches LocalStack 4.0.3 in a Podman container in detached mode (`-d`)
- Creates a custom Podman network `ls-net` so Lambda executors can
  communicate with LocalStack
- Mounts the Docker socket (`/var/run/docker.sock`) so LocalStack can run
  Lambdas in isolated containers
- Exposes ports with `-p` (bridge mapping)
- Automatically detects the WSL2 IP and tests multiple addresses
  (`127.0.0.1`, `[::1]`, WSL2 IP) for the health check
- If a container is already running, prompts whether to replace it

**Expected output:**
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

**What you learn:** Cloud services are not available instantly.
In real AWS, provisioning an SQS queue or a Lambda takes seconds. LocalStack
simulates this startup time. The *health check* pattern with retries is the
same one used by production orchestrators (Kubernetes readiness probes,
AWS ECS health checks).

The use of a custom network (`ls-net`) solves the communication problem
between LocalStack and its Lambda executors in Podman, which does not support the
link-local IPs (`169.254.1.2`) that Docker adds to the bridge.

---

#### Step 2: Create the SQS queue

```powershell
.\scripts\queues\create_queue.ps1
```

**What it does:**
- Runs `sqs create-queue` against LocalStack using the `amazon/aws-cli` image
  inside Podman
- `--network=host` is **critical**: it allows the AWS CLI container to see LocalStack
  at `127.0.0.1:4566` (without this, the container would use its own isolated network)

**Expected output:**
```
[1/2] Creating SQS queue 'cola-pedidos-ecommerce'...
  [OK] Queue created: http://127.0.0.1:4566/000000000000/cola-pedidos-ecommerce
```

**What you learn:**
- **SQS (Simple Queue Service)** is a decoupled messaging buffer. In
  traditional middleware, this is equivalent to a *JMS Queue* (TIBCO EMS, IBM MQ,
  ActiveMQ). In MuleSoft, it would be the equivalent of using the Anypoint MQ or JMS connector.
- The `QueueUrl` contains `000000000000` — this is the AWS account ID (12 digits). In
  LocalStack it is always zeros; in real AWS it would be your account ID.
- **Idempotence**: if you run the command twice, LocalStack returns the same
  URL without errors.

---

#### Step 3: Deploy API Gateway + Lambda proxy

```powershell
.\scripts\api\create_rest_api.ps1
```

**What it does:**
- Packages and deploys a proxy Lambda (`src/api_handler.py`)
- Creates an API Gateway REST with `/orders` resource and POST method
- Configures `AWS_PROXY` integration that sends HTTP requests to the proxy Lambda
- The proxy Lambda forwards the body to SQS using boto3
- Grants API Gateway permission to invoke the Lambda
- Deploys the API to a `dev` stage

**Expected output:**
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

**What you learn:**
- **API Gateway** is the HTTP entry point for REST APIs. In traditional
  middleware, it is equivalent to an API Manager or ESB with HTTP endpoints.
- **AWS_PROXY** (proxy-type integration) delegates the entire HTTP request to a
  Lambda, which is responsible for processing it and formatting the response.
- The **Lambda proxy** acts as an adaptor between the HTTP world and the
  asynchronous world of SQS, similar to an *API Proxy* in MuleSoft or an *HTTP Connector*
  in TIBCO.
- `AWS_PROXY` is used instead of direct `AWS -> SQS` integration because
  LocalStack 4.0.3 has a bug in direct service integration code
  (the moto patch expects objects but receives dictionaries).

---

#### Step 4: Package the processor Lambda

```powershell
.\scripts\lambda\package_lambda.ps1
```

**Expected output:**
```
[1/3] Preparing temp folder...
[2/3] Creating ZIP with correct structure...
[3/3] Done: C:\...\src\funcion_lambda.zip
```

**What you learn:** AWS Lambda does not receive loose source code. It needs a ZIP file
(or container image) with the code and its dependencies. In the real cloud, the
limit is 50 MB compressed. This packaging is analogous to generating a `.jar` in
MuleSoft or an `.ear` in TIBCO for deploying to a server.

---

#### Step 5: Deploy the processor Lambda function

```powershell
.\scripts\lambda\deploy_lambda.ps1
```

**What it does:**
- Checks if the function already exists (`get-function`)
- If it exists: updates only the code (`update-function-code`)
- If it does not exist: creates it with all parameters (`create-function`)
- **Waits for the function to transition from `Pending` to `Active`** using
  `lambda wait function-active-v2`

**Expected output (first time):**
```
[1/3] Checking if Lambda function 'procesador-pedidos-lambda' already exists...
  -> Function does not exist. Creating new function...
[2/3] Deploying Lambda code...
[OK] Lambda function 'procesador-pedidos-lambda' registered.
     ARN: arn:aws:lambda:us-east-1:000000000000:function:procesador-pedidos-lambda
[3/3] Waiting for function to become Active...
  [OK] Function is now Active -- ready to receive events.
```

**What you learn:**

Each parameter of `create-function` has an equivalent in traditional middleware:

| AWS Parameter | What it does | MuleSoft / TIBCO Equivalent |
|--------------|----------|------------------------------|
| `--function-name` | Service name | App name in CloudHub |
| `--runtime python3.12` | Execution environment | Mule Runtime version |
| `--role arn:aws:iam::...` | Security permissions | Roles / Policies |
| `--handler index.lambda_handler` | Code entry point | Inbound Flow |
| `--zip-file fileb://...` | Packaged code | Anypoint Studio `.jar` |

The **ARN (Amazon Resource Name)** is the universal identifier for any resource in AWS:
```
arn:partition:service:region:account:type/resource
```

The Lambda function is created in `Pending` state — just like in real AWS, where the
service needs time to prepare the execution environment.

---

#### Step 6: Connect SQS -> Lambda (THE FIX)

```powershell
.\scripts\lambda\create_trigger.ps1
```

**What it does:**
- Creates an **event source mapping** between the SQS queue and the Lambda function
- Without this, the Lambda exists but is never invoked when messages arrive in the queue

**Expected output:**
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

**What you learn (key project concept):**
- **Event Source Mapping** is the bridge between SQS (producer) and Lambda (consumer).
  Without the mapping, the Lambda is like a MuleSoft worker deployed without an inbound
  JMS endpoint.
- SQS does **periodic polling** of the Lambda: every few seconds it checks if there are
  new messages and sends them in batches of up to 10.
- The Lambda must return explicit success for SQS to delete the message.

---

#### Step 7: Test with Postman

```
POST http://127.0.0.1:4566/restapis/<api-id>/dev/_user_request_/orders
Content-Type: application/json
Body: {"id_pedido": 2001, "cliente": "postman-test", "total": 45.50}
```

**Expected output:**
```json
{
    "message": "Order received and queued",
    "messageId": "<uuid>",
    "pedido": { "id_pedido": 2001, "cliente": "postman-test", "total": 45.5 }
}
```

Or via curl:
```powershell
curl.exe -X POST http://127.0.0.1:4566/restapis/<api-id>/dev/_user_request_/orders ^
  -H "Content-Type: application/json" ^
  -d "{\"id_pedido\":2001,\"cliente\":\"test\",\"total\":45.5}"
```

**What you learn:**
- The complete synchronous-asynchronous flow: Postman receives an immediate 200 response,
  while SQS enqueues the message for asynchronous processing by the Lambda.
- The Lambda proxy is an *adaptor* that separates the HTTP protocol from background
  processing, just like an *API Proxy* in MuleSoft.

---

#### Step 8: Verify Lambda execution

```powershell
.\scripts\lambda\verify_logs.ps1
```

**Expected output:**
```
[SEARCH] Checking Lambda logs for 'procesador-pedidos-lambda'...

--- LocalStack Container Logs (last 50 lines) ---
  (no Lambda invocation entries in main container logs)

--- Lambda Executor Containers ---
  Container: localstack-pipeline-lambda-<hash>
    START RequestId: <uuid> Version: $LATEST
    Processing Order #1001
    Client: lherna06
    Total amount: 89.95 EUR
    Order #1001 integrated successfully.
    END RequestId: <uuid>
    REPORT RequestId: <uuid> Duration: xxx ms

--- CloudWatch Logs ---
  START RequestId: <uuid>
  Processing Order #1001
  ...

--- Summary ---
[OK] Queue is empty -- all messages have been consumed.
[OK] 1 Lambda executor container(s) are running.
```

**What you learn:**
- Each Lambda invocation runs in an isolated container, replicating the real AWS sandbox.
- Lifecycle: `START` -> code -> `END` + `REPORT` (duration, memory).
- CloudWatch Logs captures Python `print()` statements.
- When the handler returns 200, SQS automatically deletes the message.

---

### 3. Advanced diagnostics

```powershell
# Clean up only executor containers (leaves LocalStack running)
.\scripts\cleanup_containers.ps1

# Full log dump to logs/localstack_dump_<timestamp>.log
.\scripts\dump_logs.ps1
```

### 4. Full cleanup

```powershell
.\scripts\teardown.ps1
.\scripts\teardown.ps1 -Hard    # Force
```

---

## Concept map: AWS <-> Traditional Middleware

| Concept | AWS | MuleSoft / TIBCO |
|----------|-----|------------------|
| HTTP entry point | API Gateway | API Manager / ESB HTTP endpoint |
| HTTP -> queue adaptor | Lambda proxy | API Proxy / HTTP Connector |
| Message queue | SQS | JMS Queue / Anypoint MQ |
| Background processor | Lambda (processor) | Mule Flow / TIBCO BW Process |
| Decoupled trigger | Event Source Mapping | Inbound Endpoint / JMS Receiver |
| Event | JSON message / SQS event | Mule Message / TIBCO JMS Message |
| Permissions | IAM Role | Policy / Client ID |
| Logs | CloudWatch Logs | Mule logs / TIBCO Administrator |
| Local environment | LocalStack | Anypoint Studio / TIBCO Designer |
| IaC | AWS CLI / CloudFormation | Anypoint Studio deploy |

---

## Troubleshooting

| Symptom | Cause | Solution |
|---------|-------|----------|
| LocalStack does not start | Port 4566 in use | `netstat -ano \| findstr :4566` and kill the process |
| AWS CLI does not connect to LocalStack | Missing `--network=host` | Add `--network=host` to the `podman run` command |
| Health check cannot find LocalStack | Only accessible via WSL2 IP | The script detects the WSL2 IP automatically |
| Lambda not invoked when message is sent | Missing event source mapping | Run `create_trigger.ps1` |
| Lambda runs but no logs | LocalStack uses separate containers | `verify_logs.ps1` inspects them already |
| Lambda gives "Pending" error | The function did not finish activating | `deploy_lambda.ps1` waits for `Active` |
| SQS JSON breaks when sending | PowerShell quoting | `publish_message_to_queue.ps1` uses a temporary file |
| Container `localstack-pipeline` already exists | Previous execution | Respond "y" to the prompt or use `-Recreate` |
| Lambda executors accumulate | One container per invocation | Run `cleanup_containers.ps1` |
| API Gateway returns 404 | Stage not deployed | Check deployments with `get-deployments` |
| API Gateway returns 502 | Proxy Lambda does not exist or fails | Check proxy logs in CloudWatch |

---

## Learning summary

Upon completing this pipeline you have practiced:

1. **Event-Driven Architecture (EDA)** — complete decoupling between HTTP ingestion,
   message queue, and background processing
2. **API Gateway** — creation of REST APIs, resources, methods, `AWS_PROXY`
   integrations, stage deployment
3. **AWS Lambda** — two distinct functions: proxy (HTTP->SQS adaptor) and
   processor (business logic from SQS)
4. **AWS SQS** — queues, sending, receiving, ARNs, payload quoting
5. **Event Source Mapping** — SQS -> Lambda bridge with automatic polling
6. **LocalStack 4.x** — local emulation, custom Podman network for
   Lambda executors, health checks
7. **Podman** — rootless containers, networks, volumes, Docker socket,
   WSL2/Windows troubleshooting
8. **Advanced PowerShell** — splatting, quoting, temporary files,
   orchestration, parsing error handling
9. **Middleware patterns** — equivalents between AWS serverless and
   MuleSoft/TIBCO: API Gateway vs API Manager, Lambda proxy vs API Proxy,
   SQS vs JMS, Event Source Mapping vs Inbound Endpoint

---

## Terraform Implementation (Infrastructure as Code)

In addition to the PowerShell script-based pipeline, the project includes a
parallel implementation using **Terraform** as the Infrastructure as Code (IaC) tool.
This version replaces the imperative AWS CLI commands with declarative HCL resources,
automatically managing the creation order, dependencies, and infrastructure state.

> The original scripts in `scripts/` are kept intact as an educational
> reference. The Terraform implementation is self-contained within `terraform/`.

---

### `terraform/` directory

```
terraform/
├── versions.tf                 # Terraform and provider versions
├── provider.tf                 # AWS provider pointing to LocalStack
├── variables.tf                # Input variables
├── locals.tf                   # Local constants (names, ARNs, tags)
├── iam.tf                      # Lambda execution role and policy
├── sqs.tf                      # SQS queue
├── lambda.tf                   # Lambda functions (processor + proxy)
├── triggers.tf                 # SQS -> Lambda event source mapping + API Gateway permission
├── api_gateway.tf              # API Gateway REST + /orders resource + POST method + integration
├── outputs.tf                  # Outputs: endpoint URL, ARNs, names
├── terraform.tfvars.example    # Example variables file
│
├── lib/
│   └── Get-Terraform.ps1       # Helper: locates portable terraform.exe
│
├── download_terraform.ps1      # Downloads portable terraform.exe to tools/
├── start_localstack.ps1        # Starts LocalStack in Podman
├── stop_localstack.ps1         # Stops the LocalStack container
├── apply.ps1                   # Orchestrator: init + apply + outputs
├── destroy.ps1                 # Destroys resources + optionally stops LocalStack
├── test_message.ps1            # Sends a test order to SQS
└── verify.ps1                  # Verifies processor Lambda logs
```

---

### Description of Terraform files (.tf)

#### `versions.tf` — Version constraints

Defines the minimum Terraform (>= 1.6) and provider versions:
`hashicorp/aws` (~> 5.0) and `hashicorp/archive` (~> 2.0). The `archive` provider
is used to automatically package the Python Lambda code into ZIP files.

#### `provider.tf` — Connection to LocalStack

Configures the AWS provider to point to LocalStack instead of real AWS:

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

- `skip_*` flags: required because LocalStack uses fake credentials
  (`mock-access-key` / `mock-secret-key`) and has no real AWS metadata
- `endpoints`: each AWS service is redirected to `http://localhost:4566`
  (or the endpoint configured in `var.localstack_endpoint`)

**Key difference from the scripts:** In the PowerShell version, each AWS CLI
command runs inside a Podman container with `--network=host`. In Terraform,
the provider communicates directly with LocalStack via HTTP from the host,
without intermediary containers.

#### `variables.tf` — Parameterization

```hcl
variable "region"                { default = "us-east-1" }
variable "localstack_endpoint"   { default = "http://localhost:4566" }
variable "lambda_timeout"        { default = 30 }
variable "lambda_memory_size"    { default = 128 }
```

Allows changing the region, the LocalStack endpoint (useful if running on
WSL2 with a different IP), or the Lambda resources without modifying the
source code.

#### `locals.tf` — Project constants

Centralizes all resource names and derived values:

```hcl
locals {
  queue_name             = "cola-pedidos-ecommerce"
  processor_function_name = "procesador-pedidos-lambda"
  proxy_function_name    = "api-gateway-proxy"
  runtime                = "python3.12"
}
```

In the PowerShell scripts, these values were repeated in every file
(`create_queue.ps1`, `deploy_lambda.ps1`, `create_rest_api.ps1`, etc.).
Terraform centralizes them in one place, eliminating duplication.

#### `iam.tf` — Security (Roles and policies)

Creates a Lambda execution role with a policy that allows:

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

**Permissions granted:**
- `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents` — write
  to CloudWatch Logs
- `sqs:ReceiveMessage`, `sqs:DeleteMessage`, `sqs:GetQueueAttributes` — the
  Lambdas need these permissions to consume messages from SQS
- `sqs:SendMessage` — the proxy Lambda needs to enqueue messages

In the PowerShell version, the role was referenced with a hardcoded ARN
(`arn:aws:iam::000000000000:role/lambda-ex`). In Terraform it is created
explicitly, making it portable to real AWS.

#### `sqs.tf` — Message queue

```hcl
resource "aws_sqs_queue" "orders" {
  name                       = "cola-pedidos-ecommerce"
  visibility_timeout_seconds = 30
  max_message_size           = 262144
  message_retention_seconds  = 345600  # 4 days
}
```

Converts 3 lines of AWS CLI into a declarative resource. Terraform manages
idempotence: if the queue already exists, it does not duplicate it.

#### `lambda.tf` — Lambda functions

Uses the `archive_file` data source to automatically package the Python
code into ZIP:

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

**What it does automatically:**
- Compresses `src/index.py` into `funcion_lambda.zip`
- Uploads the ZIP to LocalStack as the function code
- If the source file changes, it detects the change via SHA256 hash and
  updates only the code (without recreating the function)
- Waits for the function to reach `Active` state

In the PowerShell scripts, this process required two separate scripts:
`package_lambda.ps1` (packaging) and `deploy_lambda.ps1` (deploy + wait).
Terraform unifies them into a single resource.

```hcl
resource "aws_lambda_function" "proxy" {
  # Same structure, but using src/api_handler.py
  handler = "api_handler.lambda_handler"
}
```

**Important note:** The `AWS_ENDPOINT_URL` environment variable is not defined.
LocalStack 4.x automatically injects the correct endpoint URL into the Lambda
executor container. If it were explicitly set to `http://localhost:4566`, the
proxy Lambda would fail because inside the executor container `localhost` points
to itself, not to LocalStack.

#### `triggers.tf` — Connections between services

Two key resources:

```hcl
# Event source mapping: SQS -> Processor Lambda
resource "aws_lambda_event_source_mapping" "sqs_to_processor" {
  event_source_arn = aws_sqs_queue.orders.arn
  function_name    = aws_lambda_function.processor.arn
  enabled          = true
  batch_size       = 10
}

# Permission: API Gateway -> Proxy Lambda
resource "aws_lambda_permission" "api_gateway_invoke_proxy" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.proxy.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${local.account_id}:${aws_api_gateway_rest_api.ecommerce.id}/*/*/*"
}
```

The **event source mapping** is the equivalent of the `create_trigger.ps1` script.
Without this resource, the processor Lambda exists but is never invoked when
messages arrive in the queue.

The **Lambda permission** is the equivalent of the `lambda add-permission` command
in `create_rest_api.ps1`. Without this permission, API Gateway cannot invoke the
proxy Lambda.

#### `api_gateway.tf` — REST API

Defines the 5 resources needed to expose the HTTP endpoint:

```hcl
resource "aws_api_gateway_rest_api" "ecommerce" { }           # The API itself
resource "aws_api_gateway_resource" "orders" { }               # The /orders resource
resource "aws_api_gateway_method" "post_orders" { }            # POST method
resource "aws_api_gateway_integration" "lambda_proxy" { }     # AWS_PROXY integration
resource "aws_api_gateway_deployment" "dev" { }                # Deployment to dev stage
```

The deployment includes a `triggers` to force a new deployment when the
integration changes:

```hcl
resource "aws_api_gateway_deployment" "dev" {
  triggers = {
    integration_hash = sha1(jsonencode(aws_api_gateway_integration.lambda_proxy))
  }
}
```

Without this trigger, Terraform would not detect that a change in the integration
requires a new deployment (a known issue with Terraform + API Gateway).

#### `outputs.tf` — Output information

```hcl
output "api_endpoint" {
  value = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.ecommerce.id}/dev/_user_request_/orders"
}
output "sqs_queue_url"           { value = aws_sqs_queue.orders.url }
output "processor_lambda_arn"    { value = aws_lambda_function.processor.arn }
output "proxy_lambda_arn"        { value = aws_lambda_function.proxy.arn }
```

Equivalent to the success messages that the PowerShell scripts displayed at
the end of each step.

---

### Supporting PowerShell scripts (in `terraform/`)

Although the infrastructure is defined in Terraform, some PowerShell scripts
are necessary for the local environment:

| Script | Function | Equivalent in `scripts/` |
|--------|---------|---------------------------|
| `start_localstack.ps1` | Starts LocalStack in Podman and waits for health check | `scripts/start_localstack.ps1` |
| `stop_localstack.ps1` | Stops or removes the LocalStack container | (new, based on `scripts/teardown.ps1`) |
| `apply.ps1` | Orchestrator: verifies LocalStack, `terraform init`, `terraform apply` | `scripts/deploy_all.ps1` |
| `destroy.ps1` | `terraform destroy` + optionally stops LocalStack | `scripts/teardown.ps1` |
| `test_message.ps1` | Sends a test JSON message to SQS | `scripts/queues/publish_message_to_queue.ps1` |
| `verify.ps1` | Inspects Lambda logs in executor containers and CloudWatch | `scripts/lambda/verify_logs.ps1` |
| `download_terraform.ps1` | Downloads portable terraform.exe to `tools/` (no global install) | (new) |
| `lib/Get-Terraform.ps1` | Helper to locate terraform.exe: `tools/` -> PATH -> download | (new) |

**Key difference:** The scripts in `scripts/` run AWS CLI commands directly.
The scripts in `terraform/` run `terraform apply` / `terraform destroy`, which in turn calls the AWS provider.

---

### Terraform execution flow

```
Postman / curl
     |
     v
API Gateway (REST)                   <- Created by: aws_api_gateway_*
     |        /orders POST
     v
Lambda proxy (api_handler.py)        <- Created by: aws_lambda_function.proxy
     |                                    Permission: aws_lambda_permission
     v
SQS "cola-pedidos-ecommerce"         <- Created by: aws_sqs_queue.orders
     |
     v
Processor Lambda                     <- Created by: aws_lambda_function.processor
     | (index.lambda_handler)            Trigger:   aws_lambda_event_source_mapping
     v
CloudWatch Logs                      <- Logs managed by the IAM role
```

**Creation order (automatically managed by Terraform):**

1. `aws_iam_role.lambda_exec` — the role must exist before the Lambdas
2. `aws_sqs_queue.orders` — the queue must exist before the trigger
3. `aws_lambda_function.proxy` + `aws_lambda_function.processor` — the
   Lambdas need the IAM role
4. `aws_lambda_event_source_mapping` — needs the queue and the Lambda
5. `aws_api_gateway_*` — needs the proxy Lambda
6. `aws_lambda_permission` — needs the proxy Lambda and the API Gateway

In the PowerShell scripts, this order was controlled manually in
`deploy_all.ps1`. Terraform resolves it automatically by analyzing the
references between resources.

---

### Comparison: Scripts vs Terraform

| Aspect | PowerShell Scripts (`scripts/`) | Terraform (`terraform/`) |
|---------|--------------------------------|--------------------------|
| **Paradigm** | Imperative (step by step) | Declarative (desired state) |
| **Idempotence** | Implemented manually with `if exists...` | Automatic (Terraform compares state) |
| **Creation order** | Orchestrated in `deploy_all.ps1` | Automatic dependency graph |
| **AWS CLI** | Executed inside Podman container | AWS provider via direct HTTP to LocalStack |
| **Lambda packaging** | Separate `package_lambda.ps1` script | Automatic `archive_file` data source |
| **Change detection** | Manual (does not detect code changes) | Automatic via `source_code_hash` |
| **Destruction** | `teardown.ps1` (ad-hoc scripts) | `terraform destroy` |
| **State** | Not managed (loose commands) | `terraform.tfstate` (tracks everything) |
| **Portability** | Windows + Podman only | Any OS + any executor |
| **Production** | No (designed only for LocalStack) | Yes (same resources work on real AWS) |

---

### Complete workflow (Terraform)

```powershell
# 0. One-time: download portable Terraform
cd terraform
.\download_terraform.ps1

# 1. Start LocalStack
.\start_localstack.ps1 -Force

# 2. Deploy all infrastructure
.\apply.ps1 -AutoApprove

# 3. Test with Postman or via script
.\test_message.ps1

# 4. Verify processor Lambda logs
.\verify.ps1

# 5. Destroy everything when done
.\destroy.ps1 -AutoApprove -AlsoStopLocalStack
```

No need to install Terraform globally: `download_terraform.ps1`
downloads the portable binary to `terraform/tools/terraform.exe`, and the
`apply.ps1` / `destroy.ps1` scripts locate it automatically via
`lib/Get-Terraform.ps1`.

---

### Concept map: Scripts -> Terraform

| Resource | PowerShell Script | Terraform Resource |
|---------|-------------------|-------------------|
| SQS queue | `scripts/queues/create_queue.ps1` | `aws_sqs_queue.orders` |
| Processor Lambda | `package_lambda.ps1` + `deploy_lambda.ps1` | `aws_lambda_function.processor` + `data.archive_file.processor` |
| Proxy Lambda | (inside `create_rest_api.ps1`) | `aws_lambda_function.proxy` + `data.archive_file.proxy` |
| SQS -> Lambda trigger | `scripts/lambda/create_trigger.ps1` | `aws_lambda_event_source_mapping.sqs_to_processor` |
| API Gateway | `scripts/api/create_rest_api.ps1` | `aws_api_gateway_rest_api` + resource + method + integration + deployment |
| API Gateway permission | (inside `create_rest_api.ps1`) | `aws_lambda_permission.api_gateway_invoke_proxy` |
| IAM role | Hardcoded as fixed ARN | `aws_iam_role.lambda_exec` + `aws_iam_role_policy.lambda_exec` |
| Wait for Active state | `lambda wait function-active-v2` | Implicitly managed by Terraform |
| Repeated variables | In each individual script | Centralized in `locals.tf` and `variables.tf` |

---

### What was learned with the Terraform implementation

1. **AWS provider with LocalStack** — configuration of custom endpoints,
   skipping credential validation, and differences between LocalStack 3.x and 4.x
2. **`archive_file` data source** — automatic Lambda packaging without external
   scripts, change detection via SHA256
3. **API Gateway + Terraform** — handling the forced deployment trigger to
   detect changes in the Lambda integration
4. **Event Source Mapping** — specific Terraform resource that connects SQS
   with Lambda, equivalent to the `create-event-source-mapping` AWS CLI command
5. **Error handling in PowerShell** — difference between `$LASTEXITCODE` and `$?`
   for external commands, especially when the executable does not exist
6. **Lambda executor networking** — understanding that `localhost:4566` inside
   the LocalStack executor container does not point to LocalStack, and that the
   environment injected by LocalStack (`AWS_ENDPOINT_URL`) manages this
   automatically if not overridden
7. **Portability vs education** — the PowerShell version is more educational
   (each command is explicitly visible), while Terraform is more suitable
   for production (declarative, stateful, portable)

---

## DynamoDB Persistence & CRUD API

The original pipeline only queued orders and logged them. A **persistence layer**
was added using DynamoDB along with a complete **CRUD API** to query,
update, and delete stored orders.

---

### Final architecture

```
Ingress flow (async):
POST /orders  →  API Gateway  →  Lambda proxy  →  SQS  →  Processor Lambda
                                                                ↓
                                                           DynamoDB (PutItem)

CRUD flow (sync):
GET  /orders          ─┐
GET  /orders/{id}      ├→  API Gateway  →  CRUD Lambda  →  DynamoDB
PUT  /orders/{id}     ─┘
DELETE /orders/{id}   ─┘
```

**Two clearly separated flows:**
- **Async write:** via SQS, just like before, but now the processor
  Lambda persists to DynamoDB
- **Synchronous read/update/delete:** directly against DynamoDB
  via a new CRUD Lambda, without going through SQS

---

### New and modified files

| File | Status | Purpose |
|---------|--------|-----------|
| `src/index.py` | Modified | Now writes to DynamoDB instead of just doing `print()` |
| `src/orders_crud.py` | New | Lambda that handles GET/PUT/DELETE against DynamoDB |
| `terraform/dynamodb.tf` | New | DynamoDB table `pedidos-ecommerce` with primary key `id_pedido` (Number) |
| `terraform/lambda.tf` | Modified | Added CRUD Lambda + `DYNAMODB_TABLE` environment variable on both Lambdas |
| `terraform/iam.tf` | Modified | DynamoDB permissions (PutItem, GetItem, UpdateItem, DeleteItem, Scan) |
| `terraform/api_gateway.tf` | Modified | GET/PUT/DELETE endpoints on `/orders` and `/orders/{id}` |
| `terraform/triggers.tf` | Modified | `lambda:InvokeFunction` permission for the CRUD Lambda |
| `terraform/outputs.tf` | Modified | New outputs: `dynamodb_table_name`, `crud_lambda_arn` |

---

### DynamoDB table

```hcl
resource "aws_dynamodb_table" "orders" {
  name         = "pedidos-ecommerce"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id_pedido"

  attribute {
    name = "id_pedido"
    type = "N"                # Number — matches the JSON input
  }
}
```

**Stored item (example):**

```json
{
  "id_pedido":      1001,
  "cliente":        "lherna06",
  "total":          89.95,
  "productos":      ["Widget A", "Gadget B"],
  "moneda":         "EUR",
  "estado":         "procesado",
  "creado_en":      "2026-06-05T10:52:26.176519+00:00",
  "actualizado_en": "2026-06-05T10:52:26.176519+00:00"
}
```

**Implementation details:**
- `billing_mode = "PAY_PER_REQUEST"` — no need to provision capacity
- `estado` allows tracking the order lifecycle (processed, completed, etc.)
- `creado_en` / `actualizado_en` — ISO 8601 timestamps for auditing
- `id_pedido` is Number because the input payload uses numeric values

---

### Processor Lambda (`src/index.py`)

The Lambda that consumes SQS messages now writes to DynamoDB:

```python
from decimal import Decimal
import json

pedido = json.loads(body_str, parse_float=Decimal)  # Float → Decimal

item = {
    'id_pedido':      pedido.get('id_pedido'),
    'cliente':        pedido.get('cliente', 'Anonymous'),
    'total':          pedido.get('total', Decimal(0)),
    'productos':      pedido.get('productos', []),
    'moneda':         pedido.get('moneda', 'EUR'),
    'estado':         'procesado',
    'creado_en':      datetime.now(timezone.utc).isoformat(),
    'actualizado_en': datetime.now(timezone.utc).isoformat(),
}

table.put_item(Item=item)
```

**Key point — `parse_float=Decimal`:** boto3 does not accept Python `float`
for writing to DynamoDB. It requires `Decimal`. By using `json.loads()` with
`parse_float=Decimal`, all decimal numbers in the JSON are automatically
converted to the correct type.

---

### CRUD Lambda (`src/orders_crud.py`)

A single Lambda that receives all requests and routes them internally:

```python
def lambda_handler(event, context):
    method   = event['httpMethod']
    resource = event['resource']

    if method == 'GET' and resource == '/orders':
        return list_orders(event)           # Scan DynamoDB
    elif method == 'GET' and resource == '/orders/{id}':
        return get_order(event)             # GetItem
    elif method == 'PUT' and resource == '/orders/{id}':
        return update_order(event)          # UpdateItem with ExpressionAttributeNames
    elif method == 'DELETE' and resource == '/orders/{id}':
        return delete_order(event)          # DeleteItem
    else:
        return respond(400, {'error': 'Unsupported route'})
```

**Implementation details:**
- **`DecimalEncoder`** — custom JSON serializer that converts `Decimal`
  to `float` for responses (`json.dumps(cls=DecimalEncoder)`)
- **`ExpressionAttributeNames`** — the CRUD Lambda uses attribute names with
  `#` prefix (e.g. `#total`, `#estado`) to avoid conflicts with DynamoDB
  reserved words (like `total` or `status`)
- **Updatable fields:** `cliente`, `total`, `productos`, `moneda`, `estado`
  — any combination sent in the PUT body

---

### Complete API endpoints

| Method | Route | Behavior | Integration |
|--------|------|----------------|-------------|
| `POST` | `/orders` | Queues the order in SQS (immediate 202 response) | Proxy Lambda (`api_handler.py`) |
| `GET` | `/orders` | Lists all orders (Scan DynamoDB) | CRUD Lambda (`orders_crud.py`) |
| `GET` | `/orders/{id}` | Returns an order by `id_pedido` | CRUD Lambda |
| `PUT` | `/orders/{id}` | Updates order fields | CRUD Lambda |
| `DELETE` | `/orders/{id}` | Deletes the order | CRUD Lambda |

**Flow of each operation:**

```
POST  2001  →  API Gateway  →  Lambda proxy  →  SQS  →  Lambda proc.  →  DynamoDB (write)
GET   /orders              →  API Gateway  →  CRUD Lambda  →  DynamoDB (Scan)
GET   /orders/2001         →  API Gateway  →  CRUD Lambda  →  DynamoDB (GetItem)
PUT   /orders/2001  {body}  →  API Gateway  →  CRUD Lambda  →  DynamoDB (UpdateItem)
DELETE /orders/2001        →  API Gateway  →  CRUD Lambda  →  DynamoDB (DeleteItem)
```

---

### Testing with Postman

After running `.\terraform\apply.ps1 -AutoApprove`, the console displays
all available endpoints. Example output:

```
Postman / curl endpoints:
---------------------------------------------------------
CREATE (async - via SQS)
  POST   http://localhost:4566/restapis/<api-id>/dev/_user_request_/orders
  Body:  {"id_pedido":1, "cliente":"Juan", "total":99.90}

LIST
  GET    http://localhost:4566/restapis/<api-id>/dev/_user_request_/orders

READ
  GET    http://localhost:4566/restapis/<api-id>/dev/_user_request_/orders/1

UPDATE
  PUT    http://localhost:4566/restapis/<api-id>/dev/_user_request_/orders/1
  Body:  {"cliente":"Juan Updated", "total":150.00, "estado":"completado"}

DELETE
  DELETE http://localhost:4566/restapis/<api-id>/dev/_user_request_/orders/1
---------------------------------------------------------
```

**Complete test sequence:**

```powershell
# 1. Send order (async)
curl.exe -X POST http://localhost:4566/restapis/<api-id>/dev/_user_request_/orders ^
  -H "Content-Type: application/json" ^
  -d "{\"id_pedido\":1001,\"cliente\":\"Test\",\"total\":99.90}"

# 2. Wait for the processor Lambda to persist it (5-10 seconds)

# 3. List all orders
curl.exe http://localhost:4566/restapis/<api-id>/dev/_user_request_/orders

# 4. Read a specific order
curl.exe http://localhost:4566/restapis/<api-id>/dev/_user_request_/orders/1001

# 5. Update the order
curl.exe -X PUT http://localhost:4566/restapis/<api-id>/dev/_user_request_/orders/1001 ^
  -H "Content-Type: application/json" ^
  -d "{\"estado\":\"completado\",\"total\":150.00}"

# 6. Delete the order
curl.exe -X DELETE http://localhost:4566/restapis/<api-id>/dev/_user_request_/orders/1001
```

---

### Concepts learned with the CRUD implementation

1. **DynamoDB + boto3** — writing with `put_item`, reading with `get_item`,
   updating with `update_item`, deleting with `delete_item`, listing with `scan`
2. **Decimal vs Float** — DynamoDB does not accept Python `float`. Use of
   `parse_float=Decimal` in `json.loads()` and custom `DecimalEncoder`
   for serializing JSON responses
3. **ExpressionAttributeNames** — DynamoDB reserved words (like `total`)
   must be referenced with `#name` in the UpdateExpression, with their mapping
   in `ExpressionAttributeNames`
4. **Single Lambda routing** — a single Lambda can handle multiple
   operations (GET/PUT/DELETE) by routing internally based on `httpMethod` and
   `resource`
5. **API Gateway + {id}** — path parameters like `/orders/{id}` reach
   the Lambda via `event['pathParameters']['id']`
6. **API Gateway deployment triggers** — when adding new endpoints, Terraform
   needs a hash trigger that detects changes and forces a new deployment
7. **Granular IAM permissions** — the CRUD Lambda policy needs
   specific permissions for each DynamoDB operation
