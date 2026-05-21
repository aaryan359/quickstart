import os
from typing import Any, Dict, List

from iii import InitOptions, Logger, register_worker
from llama_cpp import Llama

iii = register_worker(
    os.environ.get("III_URL", "ws://localhost:49134"),
    InitOptions(worker_name="inference-worker"),
)
logger = Logger()

# Model: Qwen2-0.5B-Instruct (Q4_K_M GGUF) — ~300 MB, fits on t3.micro (1 GB RAM)
# Download with:
#   huggingface-cli download Qwen/Qwen2-0.5B-Instruct-GGUF \
#     qwen2-0_5b-instruct-q4_k_m.gguf --local-dir .
MODEL_PATH = os.environ.get("MODEL_PATH", "qwen2-0_5b-instruct-q4_k_m.gguf")
MAX_NEW_TOKENS = int(os.environ.get("MAX_NEW_TOKENS", "256"))
N_CTX = int(os.environ.get("N_CTX", "2048"))

logger.info(f"Loading model from {MODEL_PATH} ...")
llm = Llama(
    model_path=MODEL_PATH,
    n_ctx=N_CTX,
    n_threads=2,   # t3.micro has 2 vCPUs
    verbose=False,
)
logger.info("Model loaded.")


def run_inference_handler(payload: Dict[str, Any]) -> Dict[str, Any]:
    messages = payload.get("messages", [])
    if not isinstance(messages, list) or not messages:
        messages = [{"role": "user", "content": payload.get("prompt", "Say hello in one short sentence.")}]

    # llama-cpp-python supports OpenAI-style chat completions natively
    response = llm.create_chat_completion(
        messages=messages,
        max_tokens=MAX_NEW_TOKENS,
        temperature=0.7,
    )

    content = response["choices"][0]["message"]["content"].strip()

    running_total = iii.trigger(
        {
            "function_id": "state::get",
            "payload": {"scope": "inference", "key": "running_total"},
        }
    )
    new_total = (running_total or 0) + 1
    iii.trigger(
        {
            "function_id": "state::set",
            "payload": {"scope": "inference", "key": "running_total", "value": new_total},
        }
    )

    return {
        "model": MODEL_PATH,
        "message": {"role": "assistant", "content": content},
        "running_total": new_total,
    }


iii.register_function("inference::run_inference", run_inference_handler)

print("Inference worker started - listening for calls")
