import { describe, it, mock, before } from 'node:test';
import assert from 'node:assert/strict';

// Mock the DynamoDB document client before importing the handler.
mock.module('@aws-sdk/lib-dynamodb', {
  namedExports: {
    DynamoDBDocumentClient: {
      from: () => ({
        send: async () => ({ Attributes: { count: 42 } }),
      }),
    },
    UpdateCommand: class UpdateCommand {
      constructor(input) {
        this.input = input;
      }
    },
  },
});
mock.module('@aws-sdk/client-dynamodb', {
  namedExports: {
    DynamoDBClient: class DynamoDBClient {},
  },
});

let handler;
before(async () => {
  ({ handler } = await import('../src/handler.js'));
});

describe('visitor-api handler', () => {
  it('returns 200 and an incremented count on POST /visitors', async () => {
    const event = { rawPath: '/visitors', requestContext: { http: { method: 'POST' } } };
    const res = await handler(event);
    assert.equal(res.statusCode, 200);
    assert.deepEqual(JSON.parse(res.body), { count: 42 });
  });

  it('returns 200 on GET /health', async () => {
    const event = { rawPath: '/health', requestContext: { http: { method: 'GET' } } };
    const res = await handler(event);
    assert.equal(res.statusCode, 200);
    assert.equal(JSON.parse(res.body).status, 'ok');
  });

  it('returns 404 for unknown routes', async () => {
    const event = { rawPath: '/nope', requestContext: { http: { method: 'GET' } } };
    const res = await handler(event);
    assert.equal(res.statusCode, 404);
  });

  it('handles CORS preflight', async () => {
    const event = { rawPath: '/visitors', requestContext: { http: { method: 'OPTIONS' } } };
    const res = await handler(event);
    assert.equal(res.statusCode, 204);
  });
});
