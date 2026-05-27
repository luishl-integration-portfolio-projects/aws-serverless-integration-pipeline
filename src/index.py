import json

def lambda_handler(event, context):
    print("--- ¡Nueva ráfaga de pedidos recibida de SQS! ---")
    
    # SQS puede enviar varios mensajes agrupados en un 'batch'
    for record in event.get('Records', []):
        # 1. Extraer el cuerpo del mensaje (el JSON de mentira que enviamos)
        body_str = record.get('body', '{}')
        body_str = body_str.lstrip('\ufeff')
        pedido = json.loads(body_str)
        
        # 2. Tu lógica de negocio (Tu componente DataWeave / Mapping)
        id_pedido = pedido.get('id_pedido', 'N/A')
        cliente = pedido.get('cliente', 'Anonimo')
        total = pedido.get('total', 0)
        
        print(f"Procesando Pedido #{id_pedido}")
        print(f"Cliente: {cliente}")
        print(f"Importe total: {total} EUR")
        
        # Aquí mas adelante conectaremos con la Base de Datos DynamoDB
        print(f"Pedido #{id_pedido} integrado con exito.")
        
    return {
        'statusCode': 200,
        'body': json.dumps('Procesamiento completado de forma asíncrona')
    }