import json
import boto3
import os
from datetime import datetime, timezone
from decimal import Decimal
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ.get('DYNAMODB_TABLE', 'pedidos-ecommerce'))


class DecimalEncoder(json.JSONEncoder):
    """Custom JSON encoder that converts Decimal to float for DynamoDB responses."""
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super().default(obj)


def respond(status, body):
    return {
        'statusCode': status,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
        },
        'body': json.dumps(body, cls=DecimalEncoder, ensure_ascii=False),
    }


def list_orders(event):
    """GET /orders — devuelve todos los pedidos (Scan)."""
    try:
        response = table.scan()
        items = response.get('Items', [])
        return respond(200, {'pedidos': items, 'total': len(items)})
    except Exception as e:
        return respond(500, {'error': str(e)})


def get_order(event):
    """GET /orders/{id} — devuelve un pedido por id_pedido."""
    try:
        id_pedido = int(event['pathParameters']['id'])
        response = table.get_item(Key={'id_pedido': id_pedido})
        item = response.get('Item')
        if not item:
            return respond(404, {'error': f'Pedido {id_pedido} no encontrado'})
        return respond(200, item)
    except Exception as e:
        return respond(500, {'error': str(e)})


def update_order(event):
    """PUT /orders/{id} — actualiza campos de un pedido."""
    try:
        id_pedido = int(event['pathParameters']['id'])
        body = json.loads(event.get('body', '{}'), parse_float=Decimal)

        update_expr = 'SET #actualizado_en = :ahora'
        expr_attr = {
            ':ahora': datetime.now(timezone.utc).isoformat(),
        }
        expr_names = {
            '#actualizado_en': 'actualizado_en',
        }

        campos_permitidos = ['cliente', 'total', 'productos', 'moneda', 'estado']
        for campo in campos_permitidos:
            if campo in body:
                attr_name = f'#{campo}'
                update_expr += f', {attr_name} = :{campo}'
                expr_attr[f':{campo}'] = body[campo]
                expr_names[attr_name] = campo

        table.update_item(
            Key={'id_pedido': id_pedido},
            UpdateExpression=update_expr,
            ExpressionAttributeNames=expr_names,
            ExpressionAttributeValues=expr_attr,
            ReturnValues='ALL_NEW',
        )

        result = table.get_item(Key={'id_pedido': id_pedido})
        return respond(200, result.get('Item', {}))
    except Exception as e:
        return respond(500, {'error': str(e)})


def delete_order(event):
    """DELETE /orders/{id} — elimina un pedido."""
    try:
        id_pedido = int(event['pathParameters']['id'])
        table.delete_item(Key={'id_pedido': id_pedido})
        return respond(200, {'message': f'Pedido {id_pedido} eliminado'})
    except Exception as e:
        return respond(500, {'error': str(e)})


def lambda_handler(event, context):
    method = event['httpMethod']
    resource = event['resource']

    if method == 'GET' and resource == '/orders':
        return list_orders(event)
    elif method == 'GET' and resource == '/orders/{id}':
        return get_order(event)
    elif method == 'PUT' and resource == '/orders/{id}':
        return update_order(event)
    elif method == 'DELETE' and resource == '/orders/{id}':
        return delete_order(event)
    else:
        return respond(400, {'error': f'Ruta no soportada: {method} {resource}'})
