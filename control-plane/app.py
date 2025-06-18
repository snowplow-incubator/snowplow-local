from base64 import b64decode, b64encode
from glob import glob
import json
import logging
import os

import docker
import requests
from flask import Flask, request
from flask_cors import CORS


app = Flask(__name__)
CORS(app)
logging.getLogger('flask_cors').level = logging.DEBUG

valid_containers = ['snowplow-stream-collector', 'snowplow-enrich', 'snowplow-iglu-server',
                    'connect', 'snowflake-streaming-loader', 'snowflake-streaming-loader-incomplete',
                    'lake-loader', 'bigquery-loader', 'snowbridge', 'ngrok-tunnel']

client = docker.from_env()

PATH = '../enrich/enrichments'
## Container API

def restart(name: str):
    try:
        if name in valid_containers:
            container = client.containers.get(name)
            container.restart()
            return {'restart': True}
        else:
            return {'restart': False, 'error': 'Invalid container name'}
    except Exception as e:
        return {'restarted': False, 'exception': str(e)}

@app.route('/containers/restart')
def restart_container():
    name = request.args.get('container')
    return restart(name)
    
@app.route('/containers/start')
def start_container():
    name = request.args.get('container')
    try:
        if name in valid_containers:
            container = client.containers.get(name)
            container.start()
            return {'start': True}
        else:
            return {'start': False, 'error': 'Invalid container name'}
    except Exception as e:
        return {'start': False, 'exception': str(e)}

@app.route('/containers/list')
def list_containers():
    containers = client.containers.list()
    output = [{'name': container.name, 'status': container.status} for container in containers if container.name in valid_containers]
    return output

@app.route('/containers/status')
def container_status():
    name = request.args.get('container')
    try:
        container = client.containers.get(name)
        return {'status': container.status}
    except Exception as e:
        return {'status': 'error', 'exception': str(e)}


## Enrichment API

## List enrichments
@app.route('/pipelines/enrichments/', methods=['GET'])
def read_enrichments():
    enrichments = []
    for filename in glob(f'{PATH}/*.json'):
        print(filename)
        with open(filename, 'r') as file:
            enrichments.append({
                **json.loads(file.read())
            })
    return enrichments

## Write single enrichment
@app.route('/pipelines/enrichments/', methods=['POST'])
def write_enrichment():
    data = request.json
    enrichment_name = data['data']['name']
    if enrichment_name == 'javascript_script_config':
        script = data['data']['parameters']['script'].encode()
        data['data']['parameters']['script'] = b64encode(script).decode('utf-8')

    with open(f'{PATH}/{enrichment_name}.json', 'w') as file:
        file.write(json.dumps(data, indent=4))
    restart('snowplow-enrich')
    return {'success': True}

## Schema API (local only)

def get_all_schemas() -> list[str]:
    # returns the contents of all schemas in the local repository
    r = requests.get('http://host.docker.internal:8081/api/schemas',
    headers={
        'apikey': os.environ.get('IGLU_SUPER_API_KEY', '')
    })
    print('response:', r.text)
    r.raise_for_status()
    return r.json()

def get_schema(iglu_uri: str, return_metadata: bool = True) -> dict:
    # todo: whether to return metadata or not...
    if return_metadata:
        repr = 'meta'
    else:
        repr = 'canonical'
    # returns a single schema by its Iglu URI
    iglu_url = iglu_uri.replace('iglu:', '')
    r = requests.get(f'http://host.docker.internal:8081/api/schemas/{iglu_url}',
        params={
            'repr': repr
        },               
        headers={
            'apikey': os.environ.get('IGLU_SUPER_API_KEY', '')
        })
    r.raise_for_status()
    return r.json()

@app.route('/schemas', methods=['POST'])
def write_schema():
    # writes (or overwrites) a schema to the local repo
    schema = request.json
    print('schema: ', schema)
    # use the Iglu Server API to upload the schema
    r = requests.post('http://host.docker.internal:8081/api/schemas', json=schema,
    headers={
        'apikey': os.environ.get('IGLU_SUPER_API_KEY', '')
    })
    print('response:', r.text)
    r.raise_for_status()
    return r.json()

@app.route('/schemas', methods=['GET'])
def list_schemas():
    schema_list = get_all_schemas()
    schemas = []
    for schema in schema_list:
        schemas.append(get_schema(schema, return_metadata=True))
    return schemas

@app.route('/validate', methods=['POST'])
def validate_schema():
    schema = request.json
    r = requests.post('http://host.docker.internal:8081/api/validation/validate/schema/jsonschema', json=schema,
    headers={
        'apikey': os.environ.get('IGLU_SUPER_API_KEY', '')
    })
    # r.raise_for_status() # do not raise
    return r.json()




    
        