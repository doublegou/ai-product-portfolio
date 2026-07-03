import os

from dotenv import load_dotenv
from openai import OpenAI


DEFAULT_MODEL = "deepseek-v4-flash"


def call_llm(messages: list[dict[str, str]]) -> str:
    """Call OpenAI and return the assistant text."""
    load_dotenv()

    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("Missing OPENAI_API_KEY. Please set it in .env.")

    model = os.getenv("MODEL", DEFAULT_MODEL).strip() or DEFAULT_MODEL
    base_url = os.getenv("OPENAI_BASE_URL", "").strip()
    client_kwargs = {"api_key": api_key}
    if base_url:
        client_kwargs["base_url"] = base_url

    client = OpenAI(**client_kwargs)

    response = client.chat.completions.create(
        model=model,
        messages=messages,
        response_format={"type": "json_object"},
        temperature=0.7,
    )

    content = response.choices[0].message.content
    if not content:
        raise RuntimeError("LLM returned empty content.")

    return content
