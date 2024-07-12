import logging
import re
import boto3
import uuid
from botocore.client import Config
from pandas import concat, json_normalize
import synapseclient
import json
from botocore.exceptions import ClientError, EventStreamError
from urllib3.exceptions import ReadTimeoutError

import os

syn = synapseclient.Synapse()
syn.login()

region_name = "us-east-1"

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Connect to AWS Bedrock
session = boto3.Session(
aws_access_key_id='abc',
aws_secret_access_key='xyz',
aws_session_token='123'
)

bedrock_agent_client = session.client("bedrock-agent-runtime", region_name=region_name)

def invokeAgent(input, agentAliasId, agentId, sessionId=None, enableTrace=False, endSession=True):

    if sessionId is None:
        sessionId = str(uuid.uuid4())

    if sessionId is not None:
        endSession = False

    try:
        response = bedrock_agent_client.invoke_agent(
            agentAliasId=agentAliasId,
            agentId=agentId,
            enableTrace=enableTrace,
            endSession=endSession,
            inputText=input,
            sessionId=sessionId
        )
        
        completion = ""
        for event in response.get("completion"):
            chunk = event["chunk"]
            completion = completion + chunk["bytes"].decode()

    except (ClientError, EventStreamError, ReadTimeoutError, TimeoutError) as e:
        logger.error(f"Couldn't invoke agent. {e}")
        raise
    except Exception as e:
        logger.error(f"An error occurred. {e}")
        raise

    return completion
    
## Get table data from synapse SELECT resourceId, resourceName, synonyms FROM syn26450069 where resourceType is Animal Model or Cell Line
query = "SELECT resourceId, resourceName, resourceType, rrid, synonyms FROM syn26450069 where resourceType in ('Animal Model', 'Cell Line')"
results = syn.tableQuery(query, includeRowIdAndRowVersion=False)
resultsdf = results.asDataFrame()

def generate_and_invoke_query(row, agentAliasId, agentId, enableTrace=False):

    query = "Please extract a comprehensive set of highly-accurate observations about '{}'".format(row['resourceName'])
    if row['resourceType']:
        query += ", a {}".format(row['resourceType'])
    if row['synonyms']:
         query += ", also known as {}".format(row['synonyms'])
    if row['resourceId']:
        query += ", resourceId: {}".format(row['resourceId'])
    if isinstance(row['rrid'], str) and row['rrid'] != 'nan':
        query += ", RRID:{}. ".format(row["rrid"])

    print(query)

    query += '. The RRID might not be mentioned in the search results. Also, the RRID is not the same as the resourceId. The resourceId is an etag and will be provided in the query. Most importantly PLEASE be sure that any observations extracted are relevant to the named resource. False negatives (i.e. missing an observation) are acceptable for now, false positives (i.e. observations attributed to the wrong resource or DOI) are not acceptable. Do not invent synonyms for cell lines or animal models that I have not explicitly provided, with the few exceptions I mention later in these instructions. Please be ABSOLUTELY SURE that the observation matches the resource. For example, if a cell line like SK-MEL-238 is queried, and the search results mention SK-MEL-2 or SK-MEL-131, these are probably not observations about SK-MEL-238 or SK-MEL-181. Or, if the search results do not explicitly mention the resource (e.g. STS-26T, or SZ-NF4 are in the query but not in the search results), then those search results probably do not contain relevant observations and should be ignored. Or, sometimes, author initials or other acronyms can be confused for a resource (e.g. cell line SZ-NF4 and author initials SZ). On the other hand, sometimes papers may mention the full name of the resource once and then refer to it thereafter using an abbrevation, particularly in the case of animal models (e.g. B6;129S2-Trp53tm1Tyj Nf1tm1Tyj/J is also known as NPcis). In that specific instance, it is OK to extract observations that do not have a perfect name match with the query resource. Similarly, sometimes there are minor differences in punctuation, spacing, or capitalization (e.g. FTC133 vs FTC-133, YST1 vs YST-1, or U87-MG vs U87MG vs U87 MG or sNF94.3 vs SNF94.3, many other examples exist); these should be treated as identical resources. If a resourceName or synonym is extremely generic - for example, Nf1+/- or NF1-mut or NF1-null or similar, do not include it in the knowledgebase search and do not extract observations about it, because it is possible that the search results are talking about a different animal model or cell line. DO NOT include observations where the focus is methodology, acknowledgements, ethics, culture conditions, quality control (e.g. <example>the cell lines were sequenced with whole genome sequencing</example>, or the <example>the cell lines were acquired from...</example>, or <example>The mouse genotypes were verified by PCR.</example>, or <example>The mice were evaluated twice daily.</example> or <example>the cell line was confirmed to be negative for mycoplasma contamination</example> or <example></example>). We are only interested in observations that are data-driven and scientific in origin. DO NOT include observations that do not match the input resource name or describe a different cell line or mouse model. Be absolutely sure that your extracted observations are accurate for a particular resource. It is not acceptable to hallucinate or make up observations. Please be sure to retrieve the "doi" portion of your response from the metadata associated with the chunk from which the observation was extracted. DO NOT make up a DOI. DO NOT respond in any format other than the requested JSON format. Missing values (for example, if the observationTime is not applicable), fill it in with a "" to make sure it is valid JSON. 000-If you do not find any relevant observations for the query resource in the search results, or there is nothing to extract, simply return [null]; do not extract anything in the "observation" format. DO NOT include any preamble to the JSON or text after the JSON. The JSON portion of your response must be valid JSON, readable in python by the json library. Be sure to wrap the JSON portion of your response in <json_response> </json_response> tags. The observations you extract should be summarized, and succinct, but we are interested in all scientific observations about the resource; even if they are complex or jargon-heavy topics, please still extract them. Here are some examples: <example_1> For the query "NF1OPG, an Animal Model, resource ID 76ff3bea-5a2c-4d9c-b3c4-513842c11af4", given the search result: <example_search_result> retrievedReferences": [{"content": {"text": "Nf1OPG mice with optic glioma tumors consistently developed preneoplastic lesions by 3 months of age that progressed to optic gliomas over the next 3 to 6 months. By 7–9 months of age, 100% of mice had symptomatic optic glioma and required euthanasia due to progressive neurological symptoms."}, "location": {"s3Location": {"uri": "s3://nf-tools-database-publications/nftc_pdfs/nftc_10.1158_1078-0432.CCR-13-1740.pdf"}, "type": "S3"}, "metadata": {"x-amz-bedrock-kb-source-uri": "s3://nf-tools-database-publications/nftc_pdfs/nftc_10.1158_1078-0432.CCR-13-1740.pdf", "doi": ["https://doi.org/10.1158/1078-0432.CCR-13-1740"]}} </example_search_result> <example_response> <json_response> [{"resourceId":"76ff3bea-5a2c-4d9c-b3c4-513842c11af4","resourceName":"NF1OPG","resourceType":["Animal Model"],"observationText":"In the NF1OPG mouse model, preneoplastic lesions consistently developed by 3 months of age and progressed to symptomatic optic gliomas requiring euthanasia by 7-9 months due to neurological symptoms in 100% of mice.","observationType":["Tumor progression","Neurological symptoms"],"observationPhase":"juvenile","observationTime":3,"observationTimeUnits":"months","doi":"https://doi.org/10.1158/1078-0432.CCR-13-1740"}] </json_response> </example_response> </example_1> <example_2> For the query "NF1 flox/flox; GFAP-Cre, an Animal Model, resource ID d2173c46-0d4d-4b79-bcdf-ceb6d05b5a3f", given the search result: <example_search_result> retrievedReferences": [{"content": {"text": "Mice with astroglial inactivation of the Nf1 tumor suppressor gene (Nf1 flox/flox; GFAP-Cre mice) developed low-grade astrocytomas with 100% penetrance. These low-grade gliomas were detected as early as 3 months of age, and the mice exhibited progressive neurological dysfunction with advanced age."}, "location": {"s3Location": {"uri": "s3://nf-tools-database-publications/nftc_pdfs/nftc_10.1158_0008-5472.CAN-05-0677.pdf"}, "type": "S3"}, "metadata": {"x-amz-bedrock-kb-source-uri": "s3://nf-tools-database-publications/nftc_pdfs/nftc_10.1158_0008-5472.CAN-05-0677.pdf", "doi": ["https://doi.org/10.1158/0008-5472.CAN-05-0677"]}} </example_search_result> <example_response> <json_response> [{"resourceId":"d2173c46-0d4d-4b79-bcdf-ceb6d05b5a3f","resourceName":"NF1 flox/flox; GFAP-Cre","resourceType":["Animal Model"],"observationText":"These mice developed low-grade astrocytomas with 100% penetrance starting as early as 3 months of age, exhibiting progressive neurological dysfunction with increasing age.","observationType":["Tumor incidence","Neurological symptoms"],"observationPhase":"juvenile","observationTime":3,"observationTimeUnits":"months","doi":"https://doi.org/10.1158/0008-5472.CAN-05-0677"}] </json_response> </example_response> </example_2> <example_3> For the query "T265, a Cell Line, resourceId 6419dd0d-1937-4ecf-bf01-876632ae0f54", given the search result: <example_search_result> retrievedReferences": [{"content": {"text": "Then we performed a human STR authentication analysis to identify any possible cross-contamination or misidentification among cell lines of human origin (Table S1). All STR profiles matched the STR profiles published in Cellosaurus and ATCC when available. However, in this process, we identified the same STR profile for ST88-14 and T265 cell lines (Data S2) in all ST88-14- and T265-related samples provided by different laboratories. To find out which cell line was misidentified we analyzed the oldest ST88-14 and T265 stored vials in their original labs and more conclusively, the primary tumor from which the ST88-14 cell line was isolated (Data S2). We identified the ST88-14 cell line as the genuine cell line for that STR profile, NF1 germline (c.1649dupT) mutation and somatic copy number alteration landscape, and dismissed the use of the T265 cell line, which we assume was misidentified at some point after its establishment and expansion."}, "location": {"s3Location": {"uri": "s3://nf-tools-database-publications/nftc_pdfs/nftc_10.1016.j.isci.2023.106096.pdf"}, "type": "S3"}, "metadata": {"x-amz-bedrock-kb-source-uri": "s3://nf-tools-database-publications/nftc_pdfs/nftc_10.1016.j.isci.2023.106096.pdf", "doi": ["https://www.doi.org/10.1016/j.isci.2023.106096"]}} </example_search_result> <example_response> <json_response> [{"resourceId":"6419dd0d-1937-4ecf-bf01-876632ae0f54","resourceName":"T265","resourceType":["Cell Line"],"observationText":"The T265 cell line was discarded as it exhibited the same STR profile as the ST88-14 and its matched primary MPNST, suggesting it may not be a distinct cell line but rather a duplicate or misidentified version of ST88-14.","observationType":["Cell line identity"],"observationPhase":"","observationTime":,"observationTimeUnits":"","doi":"https://www.doi.org/10.1016/j.isci.2023.106096"}] </json_response> </example_response> </example_3> Note that example_3 could also be a valid search result for ST88-14. <example_4> For the query "NF90-8, a Cell Line, resourceId 0f404e70-2acf-4877-bcd5-6da81d9fa41e", given the search result: <example_search_result> retrievedReferences": [{"content": {"text": "The functional impact of small variants in oncogenes and TSGs was also moderate. We identified some MPNST-related genes inactivated by pathogenic SNVs (Figure 4B and Table S3). In addition to germline NF1 mutations, somatic mutations also affected NF1, as well as other genes including TP53, PRC2 genes, and PTEN. Remarkably, we did not identify gain-of-function mutations in oncogenes, except a BRAF V600E mutation in the STS-26T cell line. In contrast, we identified gains in genomic regions containing receptors, especially a highly gained region containing PDGFRA and KIT in two NF1-related cell lines (S462 and NF90-8) (Figure 4B). The most frequently inactivated gene in our set of cell lines was CDKN2A, a known bottleneck for MPNST development.19,20 The fact that this gene was inactivated by a point mutation only in one cell line, exemplifies the relatively low functional impact of small variants compared to structural variants in MPNST initiation."}, "location": {"s3Location": {"uri": "s3://nf-tools-database-publications/nftc_pdfs/nftc_10.1016.j.isci.2023.106096.pdf"}, "type": "S3"}, "metadata": {"x-amz-bedrock-kb-source-uri": "s3://nf-tools-database-publications/nftc_pdfs/nftc_10.1016.j.isci.2023.106096.pdf", "doi": ["https://www.doi.org/10.1016/j.isci.2023.106096"]}} </example_search_result> <example_response> <json_response> [{"resourceId":"0f404e70-2acf-4877-bcd5-6da81d9fa41e","resourceName":"NF90-8","resourceType":["Cell Line"],"observationText":"The NF90-8 cell line had a highly gained region in chromosome 4 containing the PDGFRA and KIT receptors.","observationType":["Genomics"],"observationPhase":"","observationTime":,"observationTimeUnits":"","doi":"https://www.doi.org/10.1016/j.isci.2023.106096"}] </json_response> </example_response> </example_4>'

    sessionId = str(uuid.uuid4())
    
    for _ in range(100):
        # for the first loop, invoke the agent as is and convert the response to a data frame
        if _ == 0:
            first_response = invokeAgent(query, agentAliasId, agentId, sessionId, enableTrace, endSession=False)

            #extract text between <json_response> and </json_response> tags
            first_response = first_response[first_response.find("<json_response>") + len("<json_response>"):first_response.find("</json_response>")]
            print(first_response)

            if first_response.strip() == '[null]' or first_response.strip() == 'null' or first_response.strip() == '' or first_response.strip() == '[]':
                print('response is null, likely no observations to extract')
                response = json_normalize({})
                break

            try:
                response = json_normalize(json.loads(first_response))
            except:
                print('response is not json, likely no observations to extract')
                response = json_normalize({})
                break

        else:
            # for subsequent loops, modify the input to prompt the agent to continue extracting observations about the same resource
            query = "Those observations are great. I would like more unique and highly-accurate observations. I am not interested in observations that convey the same or nearly the same information as what you already shared. Tell me some additional, not previously mentioned observations about {}. Please be sure to follow all the instructions in my first prompt, and most importantly please be sure that any observations extracted are relevant to the named resource. False negatives are acceptable for now, false positives (i.e. observations attributed to the wrong resource or DOI) are not acceptable.".format(row['resourceName'])
            # if row['resourceType']:
            #     query += ", a {}".format(row['resourceType'])
            # if row['synonyms']:
            #      query += ", also known as {}".format(row['synonyms'])
            # query += ", resource ID {}. DO NOT include observations that are the same fact as a previous observation, even if phrased differently.  DO NOT include observations where the primary focus is methodology (e.g. <example>the cell lines were sequenced with whole genome sequencing</example>, or the <example>the cell lines were acquired from...</example>,), or acknowledgements. DO NOT include observations that do not match the input resource name or describe a different cell line or mouse model, even if it is a slight variant.Please be sure to retrieve the 'doi' portion of your response from the metadata associated with the chunk from which the observation was extracted. DO NOT respond in any format other than the requested JSON format. DO NOT include any preamble to the JSON or text after the JSON.  Be sure to wrap the JSON portion of your response in <json_response> </json_response> tags.".format(row['resourceId'])

            response_addl = invokeAgent(query, agentAliasId, agentId, sessionId, enableTrace, endSession=False)
            
            #extract text between <json_response> and </json_response> tags
            response_addl = response_addl[response_addl.find("<json_response>") + len("<json_response>"):response_addl.find("</json_response>")]
            print(response_addl)

            # if response is 'null' break the loop
            if response_addl.strip() == '[null]' or response_addl.strip() == 'null' or response_addl.strip() == '' or response_addl.strip() == '[]':
                print('response is null, likely no more observations to extract')
                break

            #check if the response is json format, if so, convert to a data frame and append it to the response data frame, if not, break the loop
            try:
                response_addl = json_normalize(json.loads(response_addl))
            except:
                print('response is not json, likely no more observations to extract')
                break

            response = concat([response, response_addl], ignore_index=True)
    
    try:
        print(response)
        return response
        
    except:
        response = json_normalize({})


#test the function on a single row
# row = resultsdf.sample(1).iloc[0]
# response = generate_and_invoke_query(row, agentAliasId="1WW2I8WCXL", agentId="RMYQ6X4RLO")
# print(response)

## create output directory
os.makedirs('/Users/rallaway/Documents/GitHub/nftc-llm/nftc_observations', exist_ok=True)

#run the function on rows, and write each response to a csv file, save as observation_<resourceId>.csv
responses = json_normalize({})
# sessionId_input = str(uuid.uuid4())
start_resourceId = '02dacc42-ea46-48fb-a4df-7a875d801086'
start_index = resultsdf[resultsdf['resourceId'] == start_resourceId].index[0]

for i, row in resultsdf.iloc[start_index:].iterrows():
    resourceId = row['resourceId']
    try:
        response = generate_and_invoke_query(row, agentAliasId="Y0EVOIL88H", agentId="RMYQ6X4RLO")
        if response is not None:
            response.to_csv(f'/Users/rallaway/Documents/GitHub/nftc-llm/nftc_observations/observation_{resourceId}.csv', index=False)
    except Exception as e:
        print(f"Error occurred for resourceId {resourceId}: {str(e)}")
