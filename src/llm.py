import os

from dotenv import load_dotenv
from openai import OpenAI


DEFAULT_MODEL = "gpt-4.1-mini"


def call_llm(messages: list[dict[str, str]]) -> str:
    """Call OpenAI and return the assistant text."""
    load_dotenv()

    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("Missing OPENAI_API_KEY. Please set it in .env.")

    model = os.getenv("MODEL", DEFAULT_MODEL).strip() or DEFAULT_MODEL
    client = OpenAI(api_key=api_key)

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
