import { registerWorker, Logger } from 'iii-sdk';

const iii = registerWorker(process.env.III_URL ?? 'ws://localhost:49134');
const logger = new Logger();

iii.registerFunction(
  'inference::get_response',
  async (payload: { messages?: Array<Record<string, unknown>>; prompt?: string } & Record<string, unknown>) => {
    logger.info('inference::get_response called in TypeScript', payload);

    const result = await iii.trigger({
      function_id: 'inference::run_inference',
      payload,
    });

    return result;
  },
);

iii.registerFunction(
  'http::run_inference',
  async (payload: { body: { messages?: Array<Record<string, unknown>>; prompt?: string } }) => {
    try {
      const result = await iii.trigger({
        function_id: 'inference::get_response',
        payload: payload.body,
      });
      // If result is an Error object, surface it properly
      if (result instanceof Error) {
        return {
          status_code: 503,
          body: { error: result.message },
          headers: { 'Content-Type': 'application/json' },
        };
      }
      return {
        status_code: 200,
        body: result,
        headers: { 'Content-Type': 'application/json' },
      };
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      logger.error('http::run_inference failed', { error: message });
      return {
        status_code: 503,
        body: { error: message },
        headers: { 'Content-Type': 'application/json' },
      };
    }
  },
);

iii.registerTrigger({
  type: 'http',
  function_id: 'http::run_inference',
  config: { api_path: '/v1/chat/completions', http_method: 'POST' },
});


console.log('Caller worker started - listening for calls');
