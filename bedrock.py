import boto3
import pprint
from botocore.client import Config
import re

region_name = "us-east-1"
pp = pprint.PrettyPrinter(indent=2)

# Connect to AWS Bedrock
session = boto3.Session(
aws_access_key_id='abc',
aws_secret_access_key='xyz',
aws_session_token='123'
)

# Connect to AWS Bedrock

model_id = 'anthropic.claude-3-sonnet-20240229-v1:0'
region_id = region_name 

bedrock_agent_client = session.client("bedrock-agent-runtime", region_name=region_name)

kbId = 'ZMHF67DY2R'



def retrieveAndGenerate(input, kbId, model_id, sessionId=None, region_id="us-east-1", temp = 0.2, top_p = 0.9):
    model_arn = f'arn:aws:bedrock:{region_id}::foundation-model/{model_id}'
    if sessionId:
        return bedrock_agent_client.retrieve_and_generate(
            input={
                'text': input
            },
            retrieveAndGenerateConfiguration={
                'type': 'KNOWLEDGE_BASE',
                'knowledgeBaseConfiguration': {
                    'knowledgeBaseId': kbId,
                    'modelArn': model_arn,
                    'generationConfiguration': {
                        'retrievalConfiguration': {
                            'vectorSearchConfiguration': {
                                'numberOfResults': 50
                            }
                        }
                    }
                }
            },
            sessionId=sessionId
        )
    else:
        return bedrock_agent_client.retrieve_and_generate(
            input={
                'text': input
            },
            retrieveAndGenerateConfiguration={
                'type': 'KNOWLEDGE_BASE',
                'knowledgeBaseConfiguration': {
                    'knowledgeBaseId': kbId,
                    'modelArn': model_arn,
                    'generationConfiguration': {
                        'inferenceConfig': {
                            'textInferenceConfig': {
                                'maxTokens': 4096,
                                #please note that these temperature and topP values are somewhat arbitrary and may need to be adjusted
                                'temperature': temp,
                                'topP': top_p
                            }
                        }
                    },
                    'retrievalConfiguration': {
                        'vectorSearchConfiguration': {
                             'numberOfResults': 50
                            }
                        }
                    }

                }

        )



# response = retrieveAndGenerate("Tell me about MPNST-SP-001, a Animal Model, resource ID 41c369b5-25f3-4285-829f-5481b41b230e.",
#                                kbId, 
#                                model_id)



def retrieve(input, kbId):
        return bedrock_agent_client.retrieve(
              knowledgeBaseId = kbId,
              retrievalQuery={
                'text': input
                },
                retrievalConfiguration={
                      'vectorSearchConfiguration': {
                            'numberOfResults': 50
                            }
                        }
                        )


# response = retrieve('Tell me about "B6;129S2-Trp53tm1Tyj Nf1tm1Tyj/J", a Animal Model',
#                                                    kbId)

response_2 = retrieveAndGenerate("Tell me about HCT 116 Cell Line also known as RRID:CVCL_0291",
                              kbId, 
                                model_id)

# result_text = str(response.get('retrievalResults'))
# #truncate response to under 25 kb
# if len(result_text) > 25000:
#       result_text = result_text[:25000] + "..."
# print(result_text)

# #extract scores from result_text 
# def extract_scores(result_text):
#     scores = re.findall(r"'score': (\d+\.\d+)", result_text)
#     return scores

# scores = extract_scores(result_text)
# print(scores)

#repeat for response_2
result_text_2 = response_2.get("citations")

retrieved_references = result_text_2[0]['retrievedReferences']
# #truncate response_2 to under 25 kb
# if len(result_text_2) > 25000:
#     result_text_2 = result_text_2[:25000] + "..."
print(retrieved_references)
# #extract scores from result_text_2
# scores_2 = extract_scores(result_text_2)
# print(scores_2)