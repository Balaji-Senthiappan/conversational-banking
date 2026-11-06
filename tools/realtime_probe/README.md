# Realtime voice probe

A standalone script that tests the Azure OpenAI Realtime deployment (`gpt-realtime-2.1`) with Priya's context and the app's actions as tools. Its purpose is to answer one question before we change the Flutter app: does the model call the right tool, in time?

## Result (6 Nov 2026)

`python realtime_probe.py --suite` gives **7 of 7 passed**:

| Said | Tool called | Model time |
|---|---|---|
| Pay Airtel | `propose_payment(P_AIRTEL)` | 0.7 s |
| A Kartel. | `propose_payment(P_AIRTEL)` | 1.9 s |
| Send Amma her money | `propose_payment(P_AMMA)` | 1.0 s |
| Move 1.5 lakh to the sweep FD | `propose_deposit(SWEEP_FD, 150000)` | 1.4 s |
| Where did my money go this month? | `get_spend_summary(summary)` | 1.0 s |
| Transfer 50,000 to my friend Ravi | none. It says Ravi isn't a saved payee. | 1.7 s |
| What's the weather in Chennai? | none. It says it can only help with banking. | 1.7 s |

"Model time" runs from sending the request to the tool call. The total turn time of about 10 s is mostly signing in and opening the connection. That happens once per session, not once per turn.

The suite runs in text mode. `--mic` uses the same session config and tool handling with live audio. It has not been run yet, because it needs `pyaudio` and a person speaking.

## Why the earlier attempt always gave a generic answer

The sample connects and streams audio but never sends `session.update`. Without it the session has no instructions, no tools and no customer context, so the model can only answer generically. Three other things also cause silent failures:

1. **The tool schema must be flat.** Realtime tools are `{"type": "function", "name", "description", "parameters"}`. The Chat Completions shape, `{"type": "function", "function": {...}}`, is rejected.
2. **Print `error` events.** The sample's event loop ignores them, so a rejected `session.update` looks exactly like "the model ignored my context". `session.updated` shows how many tools the session actually has.
3. **Close the tool loop.** When `response.function_call_arguments.done` arrives:
   1. Run the tool.
   2. Send `conversation.item.create` with `{"type": "function_call_output", "call_id", "output"}`.
   3. Send `response.create`.

   Without the last step the model never speaks the result.

Two smaller fixes made it reliable:

- An instruction to act on a single sound-alike payee without asking "did you mean". The confirmation sheet is where the customer checks it. This fixed the "A Kartel" case.
- "Don't announce a tool call before making it", so the model doesn't speak twice.

## Run

```bash
pip install openai azure-identity numpy pyaudio
az login
python realtime_probe.py --suite
python realtime_probe.py --text "Pay Airtel"
python realtime_probe.py --mic
```

Use `REALTIME_ENDPOINT` and `REALTIME_DEPLOYMENT` to point the probe at a different deployment. It deliberately ignores `AZURE_OPENAI_ENDPOINT`, because that variable often points at another resource. On this laptop it points at `fs-openai-1`, which made the first run fail with HTTP 400.

In `--mic` mode the script sends silence while the model is talking, so the laptop speaker doesn't trigger barge-in. `SPEAKER_RATE` (default 48000) sets the output rate, as in the sample.

## Feasibility for the app

The model side works. What's left is plumbing, and the decisions are where the Azure credential lives and who runs the tools.

**The tools run in the app.** The app already holds the customer's data and the rules engine, so the model only proposes. Each tool maps to code that already exists:

| Tool | App code |
|---|---|
| `propose_payment` | `showPaySheet` |
| `propose_deposit`, credit | `showOfferSheet` |
| `get_spend_summary` | `session.ask` plus the Ask screen |
| `navigate` | `session.go` |

The context comes from `CustomerInsights`: payees, today's items and the recommendation. It is sent in `session.update` at sign-in and again after each action.

**The credential stays off the device.** There are two ways to connect:

| | A. WebSocket relay | B. WebRTC with a short-lived key |
|---|---|---|
| How | A small Python service holds the Entra credential, and the app streams PCM to it over a WebSocket. | A small token service mints a client secret (`/openai/v1/realtime/client_secrets`), and the app connects to Azure directly over WebRTC (`flutter_webrtc`). The tools travel on the data channel. |
| Audio in Flutter | You write mic capture and PCM playback yourself. Echo cancellation is your problem, as in the sample. | The platform handles capture, playback and echo cancellation. |
| Latency | One extra hop. | Lowest. |
| Risk | Low. It reuses this probe's code. | Need to confirm that the region and deployment support WebRTC, and that it works in the Android emulator. |

Recommendation: start with B because of echo cancellation and audio playback, and keep A as the fallback. Either way, the current device recogniser stays as the offline fallback, and the model never gets a tool that pays.
