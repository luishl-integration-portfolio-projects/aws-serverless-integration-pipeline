import json
import boto3
import os
from datetime import datetime, timezone
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ.get('DYNAMODB_TABLE', 'pedidos-ecommerce'))


def lambda_handler(event, context):
    print("--- Nueva rafaga de pedidos recibida de SQS ---")

    for record in event.get('Records', []):
        body_str = record.get('body', '{}')
        body_str = body_str.lstrip('\ufeff')
        # Convert floats to Decimal for DynamoDB compatibility
        pedido = json.loads(body_str, parse_float=Decimal)

        id_pedido = pedido.get('id_pedido')
        cliente = pedido.get('cliente', 'Anonimo')
        total = pedido.get('total', Decimal(0))
        productos = pedido.get('productos', [])
        moneda = pedido.get('moneda', 'EUR')

        ahora = datetime.now(timezone.utc).isoformat()

        item = {
            'id_pedido':      id_pedido,
            'cliente':        cliente,
            'total':          total,
            'productos':      productos,
            'moneda':         moneda,
            'estado':         'procesado',
            'creado_en':      ahora,
            'actualizado_en': ahora,
        }

        try:
            table.put_item(Item=item)
            print(f"Pedido #{id_pedido} guardado en DynamoDB.")
            print(f"  Cliente: {cliente} | Total: {total} {moneda}")
            print(f"  Estado: procesado")
        except Exception as e:
            print(f"Error guardando pedido #{id_pedido} en DynamoDB: {e}")

    return {
        'statusCode': 200,
        'body': json.dumps('Procesamiento completado de forma asincrona'),
    }
