import json
import boto3


def lambda_handler(event, context):
    agent = event['agent']
    actionGroup = event['actionGroup']
    function = event['function']
    query = event.get('parameters', [])
    
    query_dict = {param['name'].lower(): str(param['value']) for param in query}
    
    input = "Tell me about {}".format(query_dict['resourcename'])
    if 'resourcetype' in query_dict:
        input += " {}".format(query_dict['resourcetype'])
    if 'synonyms' in query_dict:
        input += " also known as {}".format(query_dict['synonyms'])
    if 'rrid' in query_dict:
        input += " also known as RRID:{}".format(query_dict['rrid'])

    print(input)
    
    region_name = "us-east-1"

    # Connect to AWS Bedrock
    session = boto3.Session()

    model_id = 'anthropic.claude-3-sonnet-20240229-v1:0'
    region_id = region_name 

    bedrock_client = session.client("bedrock-agent-runtime", region_name=region_name)

    kbId = 'ZMHF67DY2R'

    model_arn = f'arn:aws:bedrock:{region_id}::foundation-model/{model_id}'
    
    # result_text = bedrock_client.retrieve_and_generate(
    #         input={
    #             'text': input
    #         },
    #         retrieveAndGenerateConfiguration={
    #             'type': 'KNOWLEDGE_BASE',
    #             'knowledgeBaseConfiguration': {
    #                 'knowledgeBaseId': kbId,
    #                 'modelArn': model_arn,
    #                 'generationConfiguration': {
    #                     'inferenceConfig': {
    #                         'textInferenceConfig': {
    #                             'maxTokens': 4096,
    #                             #please note that these temperature and topP values are somewhat arbitrary and may need to be adjusted
    #                             'temperature': 0.2,
    #                             'topP': 0.9
    #                         }
    #                     }
    #                 },
    #                 'retrievalConfiguration': {
    #                     'vectorSearchConfiguration': {
    #                          'numberOfResults': 50
    #                         }
    #                     }
    #                 }

    #             }

    #     )
    
    # print(result_text.get('citations'))
    
    # responseBody = {
    #     'TEXT' : { 
    #         "body" : str(result_text.get('citations'))
            
    #     }
        
    # }


    response = bedrock_client.retrieve(
              knowledgeBaseId = kbId,
              retrievalQuery={
                'text': input
                },
                retrievalConfiguration={
                      'vectorSearchConfiguration': {
                            'numberOfResults': 50,
                            'overrideSearchType' : 'HYBRID'
                            }
                        }
                        )

    result_text = str(response.get('retrievalResults'))
    #truncate response to under 25 kb
    if len(result_text) > 20000:
        result_text = result_text[:20000] + "..."
        print(result_text)

    responseBody = {
        'TEXT' : { 
            "body" : result_text
            
        }
        
    }
        
    action_response = {
        'actionGroup': actionGroup,
        'function': function,
        'functionResponse': {
            'responseBody': responseBody
        }

    }

    dummy_function_response = {'response': action_response, 'messageVersion': event['messageVersion']}
    print("Response: {}".format(dummy_function_response))

    return dummy_function_response
