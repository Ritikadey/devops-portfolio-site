import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, UpdateCommand } from '@aws-sdk/lib-dynamodb';

const TABLE_NAME = process.env.VISITORS_TABLE || 'devops-portfolio-visitors';
const ALLOWED_ORIGIN = process.env.ALLOWED_ORIGIN || '*';

const client = new DynamoDBClient({});
const ddb = DynamoDBDocumentClient.from(client);

const corsHeaders = {
  'Access-Control-Allow-Origin': ALLOWED_ORIGIN,
  'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  'Access-Control-Allow-Headers': 'content-type',
  'Content-Type': 'application/json',
};

function respond(statusCode, body) {
  return { statusCode, headers: corsHeaders, body: JSON.stringify(body) };
}

/**
 * Increments and returns the visitor count.
 * Uses a single DynamoDB item (pk = "visitors") with an atomic ADD update,
 * so concurrent requests never lose an increment.
 */
async function incrementVisitors() {
  const result = await ddb.send(
    new UpdateCommand({
      TableName: TABLE_NAME,
      Key: { pk: 'visitors' },
      UpdateExpression: 'ADD #count :inc',
      ExpressionAttributeNames: { '#count': 'count' },
      ExpressionAttributeValues: { ':inc': 1 },
      ReturnValues: 'UPDATED_NEW',
    })
  );
  return result.Attributes?.count ?? 0;
}

export const handler = async (event) => {
  const method = event?.requestContext?.http?.method || event?.httpMethod || 'GET';
  const rawPath = event?.rawPath || event?.path || '/';

  if (method === 'OPTIONS') {
    return respond(204, {});
  }

  try {
    if (rawPath.endsWith('/health')) {
      return respond(200, { status: 'ok', service: 'visitor-api' });
    }

    if (rawPath.endsWith('/visitors') && method === 'POST') {
      const count = await incrementVisitors();
      return respond(200, { count });
    }

    return respond(404, { error: 'not found' });
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('handler error', err);
    return respond(500, { error: 'internal error' });
  }
};
