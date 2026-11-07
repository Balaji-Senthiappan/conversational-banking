# Parked items

Things we know about and will fix later. Each one also has a `TODO(parked)` comment at the place in the code where the fix goes.

| # | Item | Where | Branch |
|---|---|---|---|
| 1 | **Weekend spends don't follow the real calendar.** The mock history is moved by whole months to follow the clock. That keeps day-of-month patterns ("paid on the 5th") but not weekdays. So "Dining out is up, mostly on weekends" and "Show weekends" can contradict the calendar. On Saturday 7 Nov 2026 the claim rests on one weekend day (Sunday 1 Nov), and in other months the "Saturdays" land on weekdays. Fix: place dining spends on the real Saturdays and Sundays of each shifted month, and only claim "mostly on weekends" once a full weekend has passed. | `lib/data/mock_bank.dart` (Priya's food spends), `lib/engine/insights.dart` (`spendSummary` insight) | both |
| 2 | **Live voice is slow to connect and sometimes fails.** "AI · live" can take 15–30 s after sign-in, one start gave a connection error, and until it connects the mic quietly uses the device recogniser, which never speaks. Ideas: connect during the sign-in checklist, retry once with a fresh key, keep the fallback message visible, and time each connection step. | `lib/speech/realtime_voice.dart` (`connect`) | `feature/realtime-voice` |
