# AI Mode banking mock (Flutter)

A clickable mock of the signed-off "AI-Led Conversational Banking" concept screens:

1. **Today for you**: the payments you usually make around now, one tap each.
2. **Make it work harder / Stay ahead of cash flow**: the product recommendation.
3. **Ask**: "Where did my money go this month?" with follow-ups.

There are no menus. You move around with the chips, the buttons and the assistant bar ("Speak or type").

## Run

```bash
flutter run -d chrome
```

You can also run `run-web.cmd`, which serves a release build at http://localhost:8085.

## Sign in

The login screen follows the client's existing mobile app, from top to bottom:

- "Welcome Back" and "Login to Continue"
- the customer
- "Enter MPIN" with one box per digit
- "Forgot MPIN?"
- "Need Help?"
- "Version 4.0.1"

There is no login-name field, because the phone already knows who the customer is. The demo starts with **Priya**. Type her MPIN and she is signed in as soon as the fourth digit goes in, so there is no Log in button.

To demo Rajesh, tap **Priya ⌄** and pick him from the list. "Forgot MPIN?" and "Need Help?" only show a note, since they aren't part of the demo.

These are the only valid logins. The usernames and digits-only mobile numbers are still accepted by `MockBankApi.authenticate`; the screen uses the username.

| Customer | Login | MPIN | What their data leads to |
|---|---|---|---|
| Priya Sharma, salaried | `priya.sharma`, `919876500001` or `9876500001` | 1111 | ₹1,85,000 idle in savings, so the app suggests moving ₹1,50,000 to an Auto-sweep FD |
| Rajesh Iyer, business | `rajesh.iyer`, `919876500002` or `9876500002` | 2222 | Current account projected to go negative later this month, so the app offers a ₹1,50,000 overdraft |

The persona is not picked in the UI. It comes from the customer's data.

## Date and time

The greeting ("Good morning / afternoon / evening") and the day of the month ("It's the 6th") come from the device clock. The mock transaction history is moved to the current month, so "this month so far" always has data. Dates later than today are left out.

Because of this, the Today cards, totals and spends change with the date. The figures in the signed-off concept are the ones for 5 Nov 2026, and the tests pin that date.

## How the numbers are worked out

Everything is computed in `lib/engine/insights.dart` from the mock data. No figure is hard-coded on a screen.

- **Usual payments**: detected from transaction history. A payee paid on a monthly or weekly rhythm becomes a "you usually…" card. Bill amounts and due dates come from presented bills (BBPS, card statement).
- **Projected cash flow**: for the next 30 days, today's balance plus expected inflows (salary, receivables) minus expected payments.
- **Available to invest**: balance, minus what is due before the next salary, minus a ₹5,000 buffer, rounded down to ₹10,000. This goes into the Sweep FD because it stays accessible. A locked FD also keeps aside an estimate of spend until salary day.
- **Credit need**: the lowest projected balance plus a ₹25,000 buffer, rounded up to ₹50,000, provided the credit score is 700 or above.
- **Spend insight**: the category that grew most against the same point last month. The cap is the average of the last 3 full months.

Product rates in `productCatalogue` are illustrative only.

The assistant (`lib/engine/assistant.dart`) uses keyword matching as a stand-in for the private LLM. Try "Pay Amma", "Pay all", "Move ₹1,50,000 to the sweep FD", "Get the overdraft", "Where did my money go?" or "Show weekends".

## After an action

- Confirming a payment, deposit or credit shows a spinner for 0.5, 1 or 1.5 seconds, chosen at random, so it feels like a real round trip.
- When the action succeeds, the app returns to Today and clears the chat.
- A paid card on Today shows "Paid" and an **×**. Tap the × to close the card. Unpaid cards have no ×, so nothing due can be hidden by mistake.
- If the assistant doesn't understand you outside the Ask screen, you stay where you are. A hint appears above the input, for example: Didn't get "…". Try "Pay Amma".
- Payee names tolerate small mishearings, so "A Kartel" is taken to mean Airtel.

## Voice

- **Tap the mic** to speak. The app uses the device's speech recogniser (`speech_to_text`), preferring Indian English. Words appear as you speak. It stops after 3 seconds of silence, or when you tap again, and the text is then sent to the assistant.
- **Long-press the mic** for the demo voice. It "hears" the phrase in the hint, which is a safe fallback for live demos. It also takes over automatically if the device has no recogniser.
- **Web:** works in Chrome or Edge. Firefox has no speech support.
- **Android emulator:** use a system image *with Google Play*. Each emulator session, open **Extended controls (⋯) → Microphone** and turn on **"Virtual microphone uses host audio input"**.
- The engine is behind `SpeechInput` (`lib/speech/speech_input.dart`), so a self-hosted speech-to-text server can replace it later.

## Data model additions

The team's model is kept, and these entities are added for this scenario (`lib/data/models.dart`):

- `Payee`: who money goes to. Needed to detect recurring payments.
- `DailyBalance`: end-of-day balance. Drives "idle for N days".
- `BillDue`: a presented bill with amount and due date.
- `ExpectedInflow`: receivables or invoices, for business cash flow.
- `ProductOffer`: the product catalogue.
- `Transaction.category` and `Transaction.payeeId`.
- `FixedDeposit.productCode` and `LoanAccount.productCode`.

## Presenter walkthrough

`walkthrough/index.html` is a 10-minute, step-by-step walkthrough of the demo on a map of the target services (the bank's channel API, AI agent, private LLM, rules engine, Oracle FLEXCUBE, payments hub). Open it in a browser and step through with the arrow keys or a clicker. Press `T` for the clock and `N` for presenter notes. The payloads and reference numbers in it are illustrative.

## Tests

```bash
flutter test
```

The tests check that the engine reproduces the figures on the signed-off screens.
