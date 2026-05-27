import json
import os
import boto3

def lambda_handler(event, context):
    # API Gateway event format: body is in event['body']
    body_str = event.get('body', '{}')
    if isinstance(body_str, str):
        try:
            pedido = json.loads(body_str)
        except json.JSONDecodeError:
            pedido = {"raw": body_str, "error": "invalid JSON"}
    else:
        pedido = body_str

    # Send to SQS using the LocalStack endpoint available in the runtime
    endpoint_url = os.environ.get('AWS_ENDPOINT_URL', 'http://localhost:4566')
    sqs = boto3.client('sqs', endpoint_url=endpoint_url)

    try:
        response = sqs.send_message(
            QueueUrl=f'{endpoint_url}/000000000000/cola-pedidos-ecommerce',
            MessageBody=json.dumps(pedido)
        )
        message_id = response['MessageId']
        print(f"Mensaje encolado: {message_id} - Pedido: {pedido.get('id_pedido', 'N/A')}")
    except Exception as e:
        print(f"Error encolando mensaje: {e}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'message': 'Pedido recibido y encolado',
            'messageId': message_id,
            'pedido': pedido
        })
    }
