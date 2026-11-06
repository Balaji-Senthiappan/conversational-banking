"""Standalone probe: Azure OpenAI Realtime + customer context + tool calls.

It answers one question before we touch the Flutter app: given Priya's context
and the app's actions as tools, does the realtime model call the right tool?

Two modes:

  python realtime_probe.py --suite             # text in, text out; scripted checks, PASS/FAIL table
  python realtime_probe.py --text "Pay Airtel" # one text turn, full event log
  python realtime_probe.py --mic               # live mic and speaker, tools executed locally

The tools are executed here with canned answers that mirror the app's mock data
(lib/data/mock_bank.dart). Nothing moves money: payment and deposit tools only
create a proposal that the customer would confirm in the app.

Environment (defaults match the sample):
  REALTIME_ENDPOINT      https://<resource>.cognitiveservices.azure.com/
  REALTIME_DEPLOYMENT    deployment name, e.g. gpt-realtime-2.1
Auth: DefaultAzureCredential (az login).
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import json
import os
import sys
import time
from dataclasses import dataclass, field

from azure.identity.aio import DefaultAzureCredential, get_bearer_token_provider
from openai import AsyncOpenAI

# Own variable names on purpose: AZURE_OPENAI_ENDPOINT is often set for another resource.
ENDPOINT = os.environ.get("REALTIME_ENDPOINT", "https://1000034329-fsto-dev1-resource.cognitiveservices.azure.com/")
DEPLOYMENT = os.environ.get("REALTIME_DEPLOYMENT", "gpt-realtime-2.1")

# ---------------------------------------------------------------------------
# Customer context: what the app knows about Priya on 5 Nov 2026.
# ---------------------------------------------------------------------------
CUSTOMER = {
    "name": "Priya Sharma",
    "segment": "salaried",
    "today": "5 November 2026",
    "savings_balance": 185000,
    "payees": [
        {"id": "P_AIRTEL", "name": "Airtel postpaid", "kind": "biller", "due": 799, "reason": "Paid on the 5th for 8 months running"},
        {"id": "P_AMMA", "name": "Amma", "kind": "person", "due": 15000, "reason": "Monthly, usually between the 1st and 5th"},
        {"id": "P_CARD", "name": "Credit card bill", "kind": "card", "due": 12430, "reason": "Due 9 Nov. You usually pay in full"},
    ],
    "recommendation": {
        "product_code": "SWEEP_FD", "product": "Auto-sweep FD", "amount": 150000, "rate_pct": 7.10,
        "why": "₹1,85,000 has sat idle in savings for 41 days",
    },
}

INSTRUCTIONS = f"""
You are the voice assistant inside a bank's mobile app. Speak Indian English, briefly: one or two sentences.

You can only act through the tools. Never state an amount, rate or date that did not come from the
customer context below or from a tool result. You cannot move money: payment and deposit tools only
prepare a proposal, and the customer confirms it on screen. Say that plainly ("I've set it up, tap Pay to confirm"
for payments, "tap Confirm" for deposits). Call tools straight away; don't announce a tool call before making it.

Speech is often misheard. When what the customer says sounds like exactly one payee in the list
("A Kartel" sounds like "Airtel postpaid"), prepare that payment directly without asking "did you mean";
the confirmation screen is where they check it. Ask only when no payee, or more than one, is a reasonable match.
Never invent a payee.
If a request has nothing to do with their banking, say you can only help with their accounts here.

Customer context (JSON):
{json.dumps(CUSTOMER, ensure_ascii=False)}
""".strip()

TOOLS = [
    {
        "type": "function",
        "name": "propose_payment",
        "description": "Prepare a payment to one of the customer's known payees. The customer confirms it on screen; this does not pay.",
        "parameters": {
            "type": "object",
            "properties": {
                "payee_id": {"type": "string", "enum": [p["id"] for p in CUSTOMER["payees"]]},
                "amount": {"type": "number", "description": "Rupees. Omit to use the amount due."},
            },
            "required": ["payee_id"],
        },
    },
    {
        "type": "function",
        "name": "propose_deposit",
        "description": "Prepare a deposit booking (FD, sweep FD or RD) for the customer to confirm on screen.",
        "parameters": {
            "type": "object",
            "properties": {
                "product_code": {"type": "string", "enum": ["SWEEP_FD", "FD_1Y", "RD"]},
                "amount": {"type": "number", "description": "Rupees"},
            },
            "required": ["product_code", "amount"],
        },
    },
    {
        "type": "function",
        "name": "get_spend_summary",
        "description": "Get the customer's spending this month so far, by category, compared with the same point last month.",
        "parameters": {
            "type": "object",
            "properties": {"view": {"type": "string", "enum": ["summary", "weekends", "merchants"]}},
            "required": ["view"],
        },
    },
    {
        "type": "function",
        "name": "navigate",
        "description": "Open a screen in the app.",
        "parameters": {
            "type": "object",
            "properties": {"screen": {"type": "string", "enum": ["today", "grow", "ask"]}},
            "required": ["screen"],
        },
    },
]


def run_tool(name: str, args: dict) -> dict:
    """Canned tool results, mirroring the app's rules engine."""
    payees = {p["id"]: p for p in CUSTOMER["payees"]}
    if name == "propose_payment":
        p = payees.get(args.get("payee_id"))
        if not p:
            return {"error": "unknown payee"}
        return {"proposal_id": "P-0412", "payee": p["name"], "amount": args.get("amount") or p["due"],
                "status": "awaiting customer confirmation on screen"}
    if name == "propose_deposit":
        return {"proposal_id": "D-0413", "product_code": args.get("product_code"), "amount": args.get("amount"),
                "rate_pct": {"SWEEP_FD": 7.10, "FD_1Y": 7.25, "RD": 6.90}.get(args.get("product_code")),
                "status": "awaiting customer confirmation on screen"}
    if name == "get_spend_summary":
        return {"month_so_far": 46820, "change_vs_last_month_pct": 12,
                "categories": [{"name": "Food", "amount": 14200}, {"name": "Bills", "amount": 11800},
                               {"name": "Travel", "amount": 9100}, {"name": "Shopping", "amount": 6900}],
                "biggest_rise": "Food", "suggested_cap": 8000}
    if name == "navigate":
        return {"opened": args.get("screen")}
    return {"error": f"no such tool {name}"}


def session_config(modality: str) -> dict:
    cfg = {
        "type": "realtime",
        "instructions": INSTRUCTIONS,
        "output_modalities": [modality],
        "tools": TOOLS,
        "tool_choice": "auto",
    }
    if modality == "audio":
        cfg["audio"] = {
            "input": {"format": {"type": "audio/pcm", "rate": 24000},
                      "turn_detection": {"type": "server_vad", "silence_duration_ms": 600}},
            "output": {"format": {"type": "audio/pcm", "rate": 24000}},
        }
    return cfg


def etype(event) -> str:
    return getattr(event, "type", None) or (event.get("type") if isinstance(event, dict) else "")


# ---------------------------------------------------------------------------
# One conversation turn driven by text. Returns what happened.
# ---------------------------------------------------------------------------
@dataclass
class TurnResult:
    calls: list = field(default_factory=list)  # (name, args)
    reply: str = ""
    errors: list = field(default_factory=list)
    seconds: float = 0.0      # whole turn, including sign-in and connecting
    model_seconds: float = 0.0  # from sending the request to the first tool call or reply text


async def connect(credential):
    token = await get_bearer_token_provider(credential, "https://cognitiveservices.azure.com/.default")()
    base_url = ENDPOINT.replace("https://", "wss://").rstrip("/") + "/openai/v1"
    client = AsyncOpenAI(websocket_base_url=base_url, api_key=token)
    return client, client.realtime.connect(model=DEPLOYMENT)


async def handle_tool_calls(connection, pending: list, log) -> None:
    """Send every function result, then ask for one follow-up response."""
    for call in pending:
        try:
            args = json.loads(call.arguments or "{}")
        except json.JSONDecodeError:
            args = {}
        result = run_tool(call.name, args)
        log(f"  [tool] {call.name}({json.dumps(args)}) -> {json.dumps(result, ensure_ascii=False)}")
        await connection.conversation.item.create(item={
            "type": "function_call_output", "call_id": call.call_id, "output": json.dumps(result, ensure_ascii=False)})
    pending.clear()
    await connection.response.create()


async def text_turn(credential, utterance: str, verbose: bool) -> TurnResult:
    log = print if verbose else (lambda *_: None)
    res = TurnResult()
    start = time.perf_counter()
    client, cm = await connect(credential)
    async with client, cm as connection:
        await connection.session.update(session=session_config("text"))
        await connection.conversation.item.create(item={
            "type": "message", "role": "user", "content": [{"type": "input_text", "text": utterance}]})
        await connection.response.create()
        asked = time.perf_counter()
        pending, followups = [], 0
        async for event in connection:
            t = etype(event)
            if not res.model_seconds and t in ("response.function_call_arguments.done", "response.output_text.delta"):
                res.model_seconds = time.perf_counter() - asked
            if t not in ("response.output_text.delta", "response.function_call_arguments.delta"):
                log(f"  <- {t}")
            if t == "error":
                res.errors.append(str(getattr(event, "error", event)))
                log(f"  [error] {getattr(event, 'error', event)}")
                break
            elif t == "session.updated":
                tools = getattr(event.session, "tools", None) or []
                log(f"  session has {len(tools)} tools, tool_choice={getattr(event.session, 'tool_choice', None)}")
            elif t == "response.output_text.delta":
                res.reply += event.delta
            elif t == "response.function_call_arguments.done":
                res.calls.append((event.name, json.loads(event.arguments or "{}")))
                pending.append(event)
            elif t == "response.done":
                if pending and followups < 3:
                    followups += 1
                    await handle_tool_calls(connection, pending, log)
                else:
                    break
    res.seconds = time.perf_counter() - start
    return res


# Each case: utterance, the tool we expect (None = no tool), and argument checks.
SUITE = [
    ("Pay Airtel", "propose_payment", {"payee_id": "P_AIRTEL"}),
    ("A Kartel.", "propose_payment", {"payee_id": "P_AIRTEL"}),
    ("Send Amma her money", "propose_payment", {"payee_id": "P_AMMA"}),
    ("Move 1.5 lakh to the sweep FD", "propose_deposit", {"product_code": "SWEEP_FD", "amount": 150000}),
    ("Where did my money go this month?", "get_spend_summary", {}),
    ("Transfer 50,000 to my friend Ravi", None, {}),
    ("What's the weather in Chennai?", None, {}),
]


async def run_suite(verbose: bool) -> int:
    failures = 0
    async with DefaultAzureCredential() as credential:
        print(f"Endpoint {ENDPOINT}  deployment {DEPLOYMENT}\n")
        for utterance, want, want_args in SUITE:
            r = await text_turn(credential, utterance, verbose)
            got = r.calls[0] if r.calls else None
            ok = not r.errors and (
                (want is None and got is None) or
                (got is not None and got[0] == want and all(got[1].get(k) == v for k, v in want_args.items())))
            failures += not ok
            called = f"{got[0]}({json.dumps(got[1])})" if got else "no tool"
            print(f"{'PASS' if ok else 'FAIL'}  model {r.model_seconds:4.1f}s  turn {r.seconds:4.1f}s  {utterance!r}\n      -> {called}")
            if r.errors:
                print(f"      error: {r.errors[0]}")
            print(f"      says: {r.reply.strip()[:160]}\n")
    print(f"{len(SUITE) - failures}/{len(SUITE)} passed")
    return 1 if failures else 0


# ---------------------------------------------------------------------------
# Live mic and speaker (needs pyaudio and numpy). Audio code follows the sample.
# ---------------------------------------------------------------------------
async def run_mic() -> None:
    import numpy as np
    import pyaudio

    SOURCE_RATE, TARGET_RATE, CHUNK = 24000, int(os.environ.get("SPEAKER_RATE", "48000")), 1024
    p = pyaudio.PyAudio()

    def wasapi_output():
        for i in range(p.get_host_api_count()):
            info = p.get_host_api_info_by_index(i)
            if "WASAPI" in info.get("name", ""):
                return info.get("defaultOutputDevice")
        return None

    speaking = asyncio.Event()  # set while the model's audio is playing; mic is muted to avoid echo

    async with DefaultAzureCredential() as credential:
        client, cm = await connect(credential)
        async with client, cm as connection:
            await connection.session.update(session=session_config("audio"))
            mic = p.open(format=pyaudio.paInt16, channels=1, rate=SOURCE_RATE, input=True, frames_per_buffer=CHUNK)
            spk = p.open(format=pyaudio.paInt16, channels=1, rate=TARGET_RATE, output=True,
                         output_device_index=wasapi_output(), frames_per_buffer=CHUNK)
            loop = asyncio.get_running_loop()
            silence = b"\x00" * (CHUNK * 2)

            async def mic_loop():
                print("Speak. Try: \"Pay Airtel\", \"Where did my money go?\", \"Move 1.5 lakh to the sweep FD\". Ctrl+C to stop.")
                while True:
                    data = await loop.run_in_executor(None, mic.read, CHUNK, False)
                    # Send silence while the model talks so the speaker doesn't trigger barge-in.
                    chunk = silence if speaking.is_set() else data
                    await connection.input_audio_buffer.append(audio=base64.b64encode(chunk).decode())

            async def event_loop():
                pending = []
                async for event in connection:
                    t = etype(event)
                    if t == "error":
                        print(f"\n[error] {event.error}")
                    elif t == "session.updated":
                        print(f"[session] {len(event.session.tools or [])} tools ready")
                    elif t == "input_audio_buffer.speech_started":
                        print("\n[you are speaking]")
                    elif t == "response.output_audio.delta":
                        speaking.set()
                        src = np.frombuffer(base64.b64decode(event.delta), dtype=np.int16).astype(np.float32)
                        if len(src):
                            n = int(len(src) * TARGET_RATE / SOURCE_RATE)
                            out = np.interp(np.linspace(0, len(src), n, endpoint=False), np.arange(len(src)), src)
                            await loop.run_in_executor(None, spk.write, out.astype(np.int16).tobytes())
                    elif t == "response.output_audio_transcript.delta":
                        print(event.delta, end="", flush=True)
                    elif t == "response.function_call_arguments.done":
                        print(f"\n[tool call] {event.name} {event.arguments}")
                        pending.append(event)
                    elif t == "response.done":
                        speaking.clear()
                        if pending:
                            await handle_tool_calls(connection, pending, print)
                        else:
                            print()

            tasks = [asyncio.create_task(mic_loop()), asyncio.create_task(event_loop())]
            try:
                await asyncio.gather(*tasks)
            finally:
                for task in tasks:
                    task.cancel()
                mic.close()
                spk.close()
                p.terminate()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--suite", action="store_true", help="run the scripted text checks")
    g.add_argument("--text", help="run one text turn and print every event")
    g.add_argument("--mic", action="store_true", help="live mic and speaker")
    ap.add_argument("-v", "--verbose", action="store_true")
    a = ap.parse_args()
    if sys.platform == "win32":
        sys.stdout.reconfigure(encoding="utf-8")
    if a.suite:
        return asyncio.run(run_suite(a.verbose))
    if a.text:
        async def one():
            async with DefaultAzureCredential() as c:
                r = await text_turn(c, a.text, verbose=True)
                print(f"\ncalls: {r.calls}\nreply: {r.reply}\nerrors: {r.errors}\n{r.seconds:.1f}s")
        asyncio.run(one())
        return 0
    try:
        asyncio.run(run_mic())
    except KeyboardInterrupt:
        print("\nStopped.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
